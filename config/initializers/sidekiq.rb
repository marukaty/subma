# Sidekiq 設定（NFR-I-04: 非同期処理）
# Redis URL は ENV["REDIS_URL"] から取得
# development / test 用。本番は Cloud Tasks を使う（ADR-0003 の追記）

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
