require "anthropic"

module Classifiers
  # Tier 3: Claude API でサブスク判定する分類器（NFR-S-10 準拠）
  #
  # 役割: RuleClassifier (Tier 1) / PatternClassifier (Tier 2) でも判定できなかった
  # 取引行を Claude Sonnet に投げて subscription / non_subscription を推定する。
  #
  # セキュリティ:
  # - description 内の連続 4 桁以上の数字は "XXXX" にマスクして送信（カード番号末尾、口座番号、電話番号）
  # - user_id / firebase_uid / email は payload に含めない（呼び出し側がそもそも渡してこない設計）
  # - 本物のユーザー CSV は開発時にも触らない（AI_USAGE_GUIDELINE / fixtures はダミーのみ）
  #
  # コスト最適化:
  # - system プロンプトに cache_control: ephemeral を付け、同一ユーザーの連続インポートで使い回し
  # - Tier 1/2 で高確度のものを除外してから Tier 3 に流す（呼び出し側の責務）
  # - 最大 BATCH_SIZE 件 / リクエスト
  #
  # フォールバック:
  # - レート制限・サーバー過負荷時は指数バックオフ（最大 MAX_RETRIES 回）
  # - JSON パース失敗 / API 失敗時はその行を unclassified として返す（unknown 扱いで保存される）
  class AiClassifier
    Result = Struct.new(:classified, :unclassified, keyword_init: true)

    MODEL = :"claude-sonnet-4-6"
    BATCH_SIZE = 50
    MAX_TOKENS = 8000
    MAX_RETRIES = 3

    SYSTEM_PROMPT = <<~PROMPT.freeze
      あなたはクレジットカード取引明細を分析する専門家です。各取引について、サブスクリプション課金（定期支払い）かどうかを判定してください。

      判定基準:
      - サブスクリプション (is_subscription: true): 月額・年額の定額制サービス（動画配信 Netflix/Spotify、SaaS Adobe/Microsoft 365、AI ChatGPT Plus/Claude Pro、クラウドストレージ iCloud/Dropbox、通信キャリア、ジム会費、新聞・雑誌購読 等）
      - サブスクリプションではない (is_subscription: false): 単発購入、コンビニ・小売・飲食、ガソリン、現金引き出し、振込、税金、医療費、交通費

      推定が難しい場合は confidence を 0.5 以下にして is_subscription は最も可能性の高い方を返す。

      # レスポンス形式（**この JSON のみを返す**。説明文や ```json ... ``` フェンスを付けない）

      {
        "results": [
          {
            "id": <input id (整数)>,
            "is_subscription": true | false,
            "confidence": <0.0〜1.0 の小数>,
            "service_name": "推定サービス名" | null,
            "category": "エンタメ" | "仕事" | "学習" | "ストレージ" | "通信" | "健康" | "生活" | "その他" | null
          }
        ]
      }
    PROMPT

    # @param client [Anthropic::Client] テスト用に差し替え可能
    def initialize(client: Anthropic::Client.new)
      @client = client
    end

    # @param rows [Array<Hash>] [{ date:, description:, amount: }, ...]
    # @return [Result]
    def classify(rows)
      return Result.new(classified: [], unclassified: []) if rows.blank?

      classified = []
      unclassified = []

      # API 応答を入力行と紐付けるため一時的な id を振る
      indexed = rows.each_with_index.map { |row, i| row.merge(_ai_id: i) }

      indexed.each_slice(BATCH_SIZE) do |batch|
        ai_results = call_with_retry(batch)
        merged = merge_results(batch, ai_results)
        merged.each do |row|
          row_clean = row.except(:_ai_id)
          if row_clean[:classification].present? && row_clean[:classification] != "unknown"
            classified << row_clean
          else
            unclassified << row_clean
          end
        end
      end

      Result.new(classified: classified, unclassified: unclassified)
    end

    private

    # NFR-S-10: 連続 4 桁以上の数字を XXXX に置換
    def mask_pii(description)
      description.to_s.gsub(/\d{4,}/, "XXXX")
    end

    def call_with_retry(batch)
      attempts = 0
      begin
        attempts += 1
        call_api(batch)
      rescue Anthropic::Errors::RateLimitError,
             Anthropic::Errors::InternalServerError => e
        if attempts < MAX_RETRIES
          sleep_for = 2**attempts
          Rails.logger.warn("[AiClassifier] retryable error (attempt #{attempts}/#{MAX_RETRIES}): #{e.class.name}: #{e.message}. sleeping #{sleep_for}s")
          sleep(sleep_for) unless Rails.env.test?
          retry
        end
        Rails.logger.error("[AiClassifier] retries exhausted: #{e.message}")
        []
      rescue StandardError => e
        Rails.logger.error("[AiClassifier] unexpected error: #{e.class.name}: #{e.message}")
        []
      end
    end

    def call_api(batch)
      payload = batch.map do |row|
        {
          id: row[:_ai_id],
          date: row[:date].to_s,
          description: mask_pii(row[:description]),
          amount: row[:amount].to_s
        }
      end

      message = @client.messages.create(
        model: MODEL,
        max_tokens: MAX_TOKENS,
        system_: [
          {
            type: "text",
            text: SYSTEM_PROMPT,
            cache_control: { type: "ephemeral" }
          }
        ],
        messages: [
          {
            role: "user",
            content: "次の取引を判定してください:\n\n#{JSON.generate(payload)}"
          }
        ]
      )

      parse_response(message)
    end

    def parse_response(message)
      text_block = message.content.find { |b| b.type == :text }
      return [] unless text_block

      # 念のため ```json ... ``` フェンスがあっても抜き出す
      raw = text_block.text.to_s.strip
      raw = raw.sub(/\A```(?:json)?\s*/, "").sub(/```\s*\z/, "")

      parsed = JSON.parse(raw)
      Array(parsed["results"])
    rescue JSON::ParserError => e
      Rails.logger.warn("[AiClassifier] JSON parse failed: #{e.message}. raw=#{raw&.first(200)}")
      []
    end

    def merge_results(batch, ai_results)
      results_by_id = ai_results.index_by { |r| r["id"] }

      batch.map do |row|
        ai = results_by_id[row[:_ai_id]]
        next row.merge(classification: "unknown") unless ai

        if ai["is_subscription"]
          row.merge(
            classification: "subscription",
            classifier: "ai",
            confidence: ai["confidence"]&.to_f,
            inferred_service_name: ai["service_name"],
            inferred_category: ai["category"]
          )
        else
          row.merge(
            classification: "non_subscription",
            classifier: "ai",
            confidence: ai["confidence"]&.to_f
          )
        end
      end
    end
  end
end
