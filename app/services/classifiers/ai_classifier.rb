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
  # - 同じ取り込みの中で「店名（正規化後）＋金額」が同じ行は 1 回だけ送り、結果を全行に当てる（M-7）
  #   日付はキーに含めない（毎月の同額請求が 1 回にまとまる）。金額をキーに含める理由は
  #   ADR-0004「利用量の上限」を参照（AMAZON.CO.JP のような汎用の店名は金額で判定が変わる）
  #
  # 利用量の上限（M-7）:
  # - classify に limiter（AiUsageLimiter）を渡すと、まとめた後の行数で上限を予約し、
  #   上限を超えた分は送らずに unknown として返す（Result#skipped_count に元の行数で記録）
  #
  # フォールバック:
  # - レート制限・サーバー過負荷時は指数バックオフ（最大 MAX_RETRIES 回）
  # - JSON パース失敗 / API 失敗時はその行を unclassified として返す（unknown 扱いで保存される）
  class AiClassifier
    # skipped_count: 利用量の上限で AI に送らなかった行数（まとめる前の元の行数）
    Result = Struct.new(:classified, :unclassified, :skipped_count, keyword_init: true) do
      def initialize(classified:, unclassified:, skipped_count: 0)
        super
      end
    end

    # 代表行の判定結果を、同じキーの他の行に写すときの項目
    VERDICT_KEYS = %i[classification classifier confidence inferred_service_name inferred_category].freeze

    MODEL = :"claude-sonnet-4-6"
    BATCH_SIZE = 50
    MAX_TOKENS = 8000
    MAX_RETRIES = 3

    SYSTEM_PROMPT = <<~PROMPT.freeze
      あなたはクレジットカード取引明細を分析する専門家です。各取引について、サブスクリプション課金（定期支払い）かどうかを判定してください。

      判定基準:
      - サブスクリプション (is_subscription: true): 月額・年額の定額制サービス（動画配信 Netflix/Spotify、SaaS Adobe/Microsoft 365、AI ChatGPT Plus/Claude Pro、クラウドストレージ iCloud/Dropbox、ジム会費、新聞・雑誌購読 等）
      - サブスクリプションではない (is_subscription: false): 単発購入、コンビニ・小売・飲食、ガソリン、現金引き出し、振込、税金、医療費、交通費
      - 通信費（携帯電話・格安SIM・光回線・インターネットプロバイダの月額料金）は定額でもサブスクリプションとして扱わず、is_subscription: false とする（意図して払っている固定費のため、本アプリの可視化対象外）

      推定が難しい場合は confidence を 0.5 以下にして is_subscription は最も可能性の高い方を返す。

      # レスポンス形式（**この JSON のみを返す**。説明文や ```json ... ``` フェンスを付けない）

      {
        "results": [
          {
            "id": <input id (整数)>,
            "is_subscription": true | false,
            "confidence": <0.0〜1.0 の小数>,
            "service_name": "推定サービス名" | null,
            "category": "エンタメ" | "仕事" | "学習" | "ストレージ" | "健康" | "生活" | "その他" | null
          }
        ]
      }
    PROMPT

    # @param client [Anthropic::Client] テスト用に差し替え可能
    def initialize(client: Anthropic::Client.new)
      @client = client
    end

    # 同じ判定になる行をまとめるキー: AI に送る内容（マスク後の店名と金額）から日付を除いたもの。
    # 店名は NFKC 正規化・大文字小文字の無視・空白の詰めをしてから比べる（Tier 1 と同じ正規化。ADR-0008）
    def self.dedup_key(row)
      description = ServiceTemplate.normalize_for_match(mask_pii(row[:description])).downcase.squish
      amount = BigDecimal(row[:amount].to_s, exception: false) || row[:amount].to_s
      [ description, amount ]
    end

    # NFR-S-10: 連続 4 桁以上の数字を XXXX に置換
    def self.mask_pii(description)
      description.to_s.gsub(/\d{4,}/, "XXXX")
    end

    # @param rows [Array<Hash>] [{ date:, description:, amount: }, ...]
    # @param limiter [#reserve, nil] AI に送る行数の上限（AiUsageLimiter）。nil なら上限なし
    # @return [Result]
    def classify(rows, limiter: nil)
      return Result.new(classified: [], unclassified: []) if rows.blank?

      # 同じキーの行は先頭の 1 行（代表）だけを送る。group_by は最初に出てきた順を保つ
      groups = rows.group_by { |row| self.class.dedup_key(row) }.values
      allowed = limiter ? limiter.reserve(groups.size) : groups.size
      sent_groups = groups.first(allowed)
      skipped_groups = groups.drop(allowed)

      verdicts = classify_representatives(sent_groups.map(&:first))

      classified = []
      unclassified = []
      sent_groups.zip(verdicts).each do |members, verdict|
        known = verdict[:classification].present? && verdict[:classification] != "unknown"
        members.each do |row|
          if known
            classified << row.merge(verdict.slice(*VERDICT_KEYS))
          else
            unclassified << row.merge(classification: "unknown")
          end
        end
      end
      skipped_groups.flatten(1).each { |row| unclassified << row.merge(classification: "unknown") }

      Result.new(classified: classified, unclassified: unclassified, skipped_count: skipped_groups.sum(&:size))
    end

    private

    # 代表行を BATCH_SIZE 件ずつ送り、入力と同じ順に判定結果（行に結果を足したもの）を返す
    def classify_representatives(representatives)
      # API 応答を入力行と紐付けるため一時的な id を振る
      indexed = representatives.each_with_index.map { |row, i| row.merge(_ai_id: i) }

      indexed.each_slice(BATCH_SIZE).flat_map do |batch|
        merge_results(batch, call_with_retry(batch)).map { |row| row.except(:_ai_id) }
      end
    end

    def mask_pii(description)
      self.class.mask_pii(description)
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
