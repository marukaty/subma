# Phase 3: CSV 取り込みパイプライン（Tier 1 + Tier 2 + Tier 3）
#
# パイプライン:
#   1. Active Storage の attached file を一時パスに展開
#   2. Csv::Parser で行配列を取得
#   3. Tier 1 RuleClassifier で確定できる行を分類（confidence 1.0）
#   4. Tier 2 PatternClassifier で候補を絞り込み（confidence 0.7）
#   5. Tier 3 AiClassifier で残りを Claude API で判定（NFR-S-10 PII マスキング）
#   6. Transaction レコードに保存（classification / classifier / confidence 等）
#   7. CsvImport.status を completed に
#   8. **アップロードファイルを purge**（NFR-S-09）
#
# 失敗時は status: :failed にして CsvImport を残し、ファイルも削除する
class ProcessCsvJob < ApplicationJob
  queue_as :default

  def perform(csv_import_id)
    csv_import = CsvImport.find(csv_import_id)
    user = csv_import.user

    csv_import.update!(status: :processing)

    rows = parse_attached_file(csv_import)
    csv_import.update!(original_row_count: rows.size, status: :rule_matching)

    # Tier 1: 規則ベース
    rule_result = Classifiers::RuleClassifier.new.classify(rows)

    # Tier 2: パターン検出（Tier 1 でマッチしなかったものに対して）
    pattern_result = Classifiers::PatternClassifier.new(user: user).classify(rule_result.unclassified)

    # Tier 3: Claude API（Tier 1/2 でも判定できなかったものを AI に投げる）
    csv_import.update!(status: :ai_analyzing)
    ai_result = ai_classifier.classify(pattern_result.unclassified)

    classified_rows = rule_result.classified + pattern_result.classified + ai_result.classified
    # ai_result.unclassified は AI も判定できなかった or API 失敗で unknown 扱いで保存
    unknown_rows = ai_result.unclassified

    save_transactions(csv_import, user, classified_rows, unknown_rows)

    csv_import.update!(matched_count: classified_rows.size, status: :completed)
  rescue StandardError => e
    Rails.logger.error("[ProcessCsvJob] failed for csv_import_id=#{csv_import_id}: #{e.message}")
    csv_import&.update!(status: :failed)
    raise
  ensure
    # NFR-S-09: 処理結果に関係なくアップロードファイルは即削除
    csv_import&.purge_uploaded_file!
  end

  private

  # AI クライアントは差し替え可能（テストや将来の Tier 3 切替を想定）
  def ai_classifier
    @ai_classifier ||= Classifiers::AiClassifier.new
  end

  def parse_attached_file(csv_import)
    raise "no file attached" unless csv_import.file.attached?

    csv_import.file.blob.open do |tmp|
      Csv::Parser.new(file_path: tmp.path, format: csv_import.format).parse
    end
  end

  def save_transactions(csv_import, user, classified_rows, unknown_rows)
    Transaction.transaction do
      classified_rows.each do |row|
        Transaction.create!(
          csv_import: csv_import,
          user: user,
          transaction_date: row[:date],
          amount: row[:amount],
          description: row[:description],
          classification: row[:classification],
          classifier: row[:classifier],
          confidence: row[:confidence],
          inferred_service_name: row[:inferred_service_name],
          inferred_category: row[:inferred_category]
        )
      end

      unknown_rows.each do |row|
        Transaction.create!(
          csv_import: csv_import,
          user: user,
          transaction_date: row[:date],
          amount: row[:amount],
          description: row[:description],
          classification: :unknown
        )
      end
    end
  end
end
