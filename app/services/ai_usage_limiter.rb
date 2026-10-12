# AI（Claude API）に送る行数の上限を管理する（AI 利用料の上限。ADR-0004「利用量の上限」）。
#
# 上限は 3 つ。どれも環境変数で変更でき、0 にするとその範囲で AI を使わない。
# - 取り込み 1 回: AI_MAX_ROWS_PER_IMPORT（既定 300）
# - 1 ユーザー 1 日: AI_MAX_ROWS_PER_USER_PER_DAY（既定 500）
# - 全体 1 日: AI_MAX_ROWS_PER_DAY（既定 2,000）
#
# 数えるのは「AI に実際に送る行数」（同じ店名・金額をまとめた後の件数。AiClassifier 参照）。
# 日次の行数は DB（ai_usage_counters）で数える。Cloud Run はインスタンスが複数になりうるため、
# メモリやインスタンスごとのキャッシュでは合算できない。
# 日付の区切りはアプリのタイムゾーン（Asia/Tokyo）の 0 時。
#
# 上限を超える分は送らない（呼び出し側が unknown で保存する）。処理全体は失敗させない。
# 予約した行数は、API 呼び出しが失敗しても戻さない（課金された可能性があり、安全側に倒す）。
#
# [ai-assisted]
class AiUsageLimiter
  DEFAULT_MAX_ROWS_PER_IMPORT = 300
  DEFAULT_MAX_ROWS_PER_USER_PER_DAY = 500
  DEFAULT_MAX_ROWS_PER_DAY = 2_000

  def self.max_rows_per_import
    EnvLimit.integer("AI_MAX_ROWS_PER_IMPORT", default: DEFAULT_MAX_ROWS_PER_IMPORT, min: 0)
  end

  def self.max_rows_per_user_per_day
    EnvLimit.integer("AI_MAX_ROWS_PER_USER_PER_DAY", default: DEFAULT_MAX_ROWS_PER_USER_PER_DAY, min: 0)
  end

  def self.max_rows_per_day
    EnvLimit.integer("AI_MAX_ROWS_PER_DAY", default: DEFAULT_MAX_ROWS_PER_DAY, min: 0)
  end

  # @param user [User] 取り込みを行うユーザー（取り込み 1 回ごとに new する）
  def initialize(user:)
    @user = user
    @granted_in_import = 0
  end

  # 送りたい行数のうち、上限の範囲で送ってよい行数を予約して返す。
  # @param requested [Integer]
  # @return [Integer] 0 以上 requested 以下
  def reserve(requested)
    return 0 unless requested.positive?

    wanted = [ requested, self.class.max_rows_per_import - @granted_in_import ].min
    granted = wanted.positive? ? reserve_daily(wanted) : 0
    @granted_in_import += granted

    if granted < requested
      Rails.logger.warn("[AiUsageLimiter] limit reached user_id=#{@user.id} requested=#{requested} granted=#{granted}")
    end
    granted
  end

  private

  # 全体 → ユーザーの順に行ロックを取り、残りを確認して加算する（順序を固定してデッドロックを避ける）
  def reserve_daily(wanted)
    date = Time.zone.today
    AiUsageCounter.transaction do
      ensure_counters(date)
      global = AiUsageCounter.lock.find_by!(user_key: AiUsageCounter::GLOBAL_KEY, usage_date: date)
      mine = AiUsageCounter.lock.find_by!(user_key: @user.id, usage_date: date)

      remaining = [
        self.class.max_rows_per_day - global.rows_sent,
        self.class.max_rows_per_user_per_day - mine.rows_sent
      ].min
      granted = wanted.clamp(0, [ remaining, 0 ].max)

      if granted.positive?
        global.update!(rows_sent: global.rows_sent + granted)
        mine.update!(rows_sent: mine.rows_sent + granted)
      end
      granted
    end
  end

  # その日の行が無ければ 0 で作る（既にあれば何もしない。一意キー (user_key, usage_date)）
  def ensure_counters(date)
    AiUsageCounter.insert_all(
      [
        { user_id: nil, usage_date: date, rows_sent: 0 },
        { user_id: @user.id, usage_date: date, rows_sent: 0 }
      ]
    )
  end
end
