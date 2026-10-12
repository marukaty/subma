# CSV 取り込みパイプライン（Tier 1 + Tier 2 + Tier 3）
#
# パイプライン:
#   0. 処理権を取る（uploading → processing。ADR-0007）
#   1. Active Storage の attached file を一時パスに展開
#   2. Csv::Parser で行配列を取得し、他の取り込みで保存済みの取引を除く（再取り込みの重複防止）
#   3. Tier 1 RuleClassifier で確定できる行を分類（confidence 1.0）
#   4. Tier 2 PatternClassifier で候補を絞り込み（confidence 0.7）
#   5. Tier 3 AiClassifier で残りを Claude API で判定（NFR-S-10 PII マスキング）
#      AI に送る行数には上限がある（AiUsageLimiter。ADR-0004「利用量の上限」）。超えた分は AI に送らず unknown で保存し、
#      件数を ai_skipped_count に残す（処理は失敗させない）
#   6. Transaction レコードを作り直す（既存分を消してから保存。同じ DB トランザクション内）
#   7. CsvImport.status を completed に（matched_count = サブスクと判定した件数、skipped_duplicate_count、
#      ai_skipped_count）
#   8. **completed のときだけアップロードファイルを purge**（NFR-S-09）
#   9. 同じユーザーの待ち（uploading）があれば次を登録
#
# 冪等性（ADR-0007）:
#   Cloud Tasks は at-least-once 配信なので、同じ csv_import_id が複数回届くことがある。
#   uploading 以外（処理中・完了・失敗）の import は何もせず正常終了し、再送を止める。
#   失敗時は status: :failed と error_summary を残し、ファイルは再処理のために残す。
#   例外は外に出さない（failed は手動の再処理でだけ戻すため、Cloud Tasks に再送させない）。
#
# 再取り込みの重複（ADR-0007）:
#   同じユーザーの「取引日・利用店名・金額」が一致する取引が、他の取り込みで既に保存されていれば
#   新しくは保存しない（最初の取り込みに紐づけたまま）。同じ CSV の中で同じ取引が 2 行あるのは
#   正当な 2 件なので両方保存する。件数で突き合わせ、保存済みの件数を超えた分だけ保存する。
#
# 戻り値: :completed / :failed / :skipped / :deferred
class ProcessCsvJob < ApplicationJob
  queue_as :default

  # 行数の上限（CsvUploadForm.max_rows）を超えた CSV。アップロード時に弾くので通常は起きない
  # （上限を下げた後に、それより前にアップロードされたものを処理する場合など）
  class TooManyRowsError < StandardError; end

  def perform(csv_import_id)
    csv_import = CsvImport.find_by(id: csv_import_id)
    if csv_import.nil?
      log_info("skipped: not found", csv_import_id)
      return :skipped
    end

    claim = claim_processing(csv_import)
    return claim unless claim == :claimed

    result = run_pipeline(csv_import)
    dispatch_next_for(csv_import.user)
    result
  end

  private

  # 処理権を原子的に取る。ユーザーの行をロックして、同じユーザーの import が
  # 同時に 2 件 processing にならないようにする。
  def claim_processing(csv_import)
    CsvImport.transaction do
      User.lock.find(csv_import.user_id)
      csv_import.lock!

      unless csv_import.status_uploading?
        log_info("skipped: already #{csv_import.status}", csv_import.id)
        next :skipped
      end

      if csv_import.user.csv_imports.actively_processing.where.not(id: csv_import.id).exists?
        log_info("deferred: another import of the same user is processing", csv_import.id)
        next :deferred
      end

      csv_import.update!(status: :processing, error_summary: nil)
      :claimed
    end
  end

  def run_pipeline(csv_import)
    user = csv_import.user

    rows = parse_attached_file(csv_import)
    csv_import.update!(original_row_count: rows.size, status: :rule_matching)
    raise TooManyRowsError, "#{rows.size} rows" if rows.size > CsvUploadForm.max_rows

    # 保存済みの取引は判定（AI の呼び出し）の前に除く
    rows, skipped_duplicate_count = reject_already_imported(csv_import, user, rows)

    # Tier 1: 規則ベース
    rule_result = Classifiers::RuleClassifier.new.classify(rows)

    # Tier 2: パターン検出（Tier 1 でマッチしなかったものに対して）
    pattern_result = Classifiers::PatternClassifier.new(user: user).classify(rule_result.unclassified)

    # Tier 3: Claude API（Tier 1/2 でも判定できなかったものを AI に投げる）
    csv_import.update!(status: :ai_analyzing)
    ai_result = ai_classifier.classify(pattern_result.unclassified, limiter: AiUsageLimiter.new(user: user))

    classified_rows = rule_result.classified + pattern_result.classified + ai_result.classified
    # ai_result.unclassified は AI も判定できなかった・API 失敗・利用量の上限で送らなかった行。unknown 扱いで保存
    unknown_rows = ai_result.unclassified

    Transaction.transaction do
      save_transactions(csv_import, user, classified_rows, unknown_rows)
      # 「サブスク判定」の件数は、サブスクと判定された取引だけを数える
      # （AI が「サブスクではない」と判定した行・未判定の行は含めない）
      csv_import.update!(
        matched_count: csv_import.transactions.classification_subscription.count,
        skipped_duplicate_count: skipped_duplicate_count,
        ai_skipped_count: ai_result.skipped_count,
        status: :completed
      )
    end

    purge_file(csv_import)
    :completed
  rescue StandardError => e
    # 例外メッセージには CSV の中身が混ざることがあるので、保存するのはクラス名だけ
    Rails.logger.error("[ProcessCsvJob] failed for csv_import_id=#{csv_import.id}: #{e.class}: #{e.message}")
    csv_import.update!(status: :failed, error_summary: e.class.name.truncate(255))
    :failed
  end

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

  # 他の取り込みで保存済みの取引を除く。戻り値は [残す行, スキップした件数]。
  # 同じ取引が保存済みの件数だけスキップし、それを超えた分（同じ CSV 内の正当な複数件）は残す。
  # 自分の import の行は数えない（再実行時は save_transactions で作り直すため）。
  # 1 ユーザーの処理は同時に 1 件（claim_processing）なので、確認から保存までの間に
  # 同じユーザーの取引が他から増えることはない。
  def reject_already_imported(csv_import, user, rows)
    return [ rows, 0 ] if rows.empty?

    saved_counts = Transaction.where(user: user, transaction_date: rows.map { |row| row[:date] }.uniq)
                              .where.not(csv_import_id: csv_import.id)
                              .pluck(:transaction_date, :description, :amount)
                              .map { |date, description, amount| Transaction.dedup_key(date, description, amount) }
                              .tally

    skipped = 0
    kept = rows.reject do |row|
      key = Transaction.dedup_key(row[:date], row[:description], row[:amount])
      next false unless saved_counts.fetch(key, 0).positive?

      saved_counts[key] -= 1
      skipped += 1
      true
    end
    [ kept, skipped ]
  end

  # import 単位で作り直す。前回の途中結果が残っていても重複しないように、先に消してから保存する。
  def save_transactions(csv_import, user, classified_rows, unknown_rows)
    Transaction.where(csv_import_id: csv_import.id).delete_all

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

  # NFR-S-09: completed になったらアップロードファイルを即削除。
  # 削除に失敗しても結果は completed のまま（残ったファイルはバケットのライフサイクルで消える）
  def purge_file(csv_import)
    csv_import.purge_uploaded_file!
  rescue StandardError => e
    Rails.logger.warn("[ProcessCsvJob] purge failed for csv_import_id=#{csv_import.id}: #{e.class}")
  end

  # 同じユーザーの待ち（dispatch を見送られた uploading）があれば、古い順に 1 件登録する
  def dispatch_next_for(user)
    next_import = user.csv_imports.status_uploading
                      .joins(:file_attachment)
                      .order(:created_at, :id)
                      .first
    CsvProcessingDispatcher.dispatch(next_import) if next_import
  rescue StandardError => e
    Rails.logger.error("[ProcessCsvJob] failed to dispatch next import for user_id=#{user.id}: #{e.class}: #{e.message}")
  end

  def log_info(message, csv_import_id)
    Rails.logger.info("[ProcessCsvJob] #{message} csv_import_id=#{csv_import_id}")
  end
end
