# Sidekiq 設定（NFR-I-04: 非同期処理）
# Redis URL は ENV["REDIS_URL"] から取得
# Phase 4 で Cloud Tasks への切り替えを ADR-0003 で検討予定

redis_url = ENV.fetch("REDIS_URL", "redis://localhost:6379/0")

Sidekiq.configure_server do |config|
  config.redis = { url: redis_url }
end

Sidekiq.configure_client do |config|
  config.redis = { url: redis_url }
end
