require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# Action Mailbox / Action Text / Action Cable は使っていないため読み込まない。
# 読み込むと受信メール用・WebSocket 用のルートやミドルウェアが有効になり、
# 不要な公開エンドポイントが増える。
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Subma
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # 表示・処理タイムゾーンは日本時間（JST）。DB には UTC で保存される（active_record.default_timezone のデフォルト）。
    # ActiveRecord の timestamp 系メソッドは TimeWithZone を返し、strftime 等で自動的に JST で表示される。
    config.time_zone = "Tokyo"

    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # ActiveJob のバックエンドに Sidekiq を採用（Phase 3 ProcessCsvJob 等）
    config.active_job.queue_adapter = :sidekiq

    # Active Storage はサーバー側で CSV を attach して処理後に purge するだけで、
    # ブラウザからの直接アップロード（DirectUpload）やファイル配信は使わない。
    # 既定のルート（/rails/active_storage/direct_uploads、/rails/active_storage/disk/*、
    # blob / representation 配信）は認証なしで到達できるため描画しない。
    config.active_storage.draw_routes = false
  end
end
