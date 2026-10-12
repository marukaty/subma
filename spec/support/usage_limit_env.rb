# 利用量の上限（ADR-0004）の環境変数を example ごとに退避・復元する。
# 上限を変えて確かめる example では with_limit_env で上書きする。
module UsageLimitEnvHelper
  USAGE_LIMIT_ENV_KEYS = %w[
    CSV_MAX_ROWS
    AI_MAX_ROWS_PER_IMPORT
    AI_MAX_ROWS_PER_USER_PER_DAY
    AI_MAX_ROWS_PER_DAY
  ].freeze

  def with_limit_env(values)
    values.each { |key, value| ENV[key.to_s] = value.to_s }
  end
end

RSpec.configure do |config|
  config.include UsageLimitEnvHelper

  config.around do |example|
    originals = UsageLimitEnvHelper::USAGE_LIMIT_ENV_KEYS.index_with { |key| ENV.fetch(key, nil) }
    originals.each_key { |key| ENV.delete(key) }
    example.run
  ensure
    originals.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
