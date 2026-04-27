# Lograge 設定（NFR-I-07: Cloud Logging に構造化ログ集約）
# Cloud Run / Cloud Logging で扱いやすいよう JSON 1 行で出力

Rails.application.configure do
  config.lograge.enabled = !Rails.env.test?
  config.lograge.formatter = Lograge::Formatters::Json.new
  config.lograge.base_controller_class = "ActionController::Base"

  # Active Storage 等のノイズになる ActiveRecord マルチパートログを抑制
  config.lograge.keep_original_rails_log = false
  config.lograge.logger = ActiveSupport::Logger.new($stdout) if Rails.env.production?

  config.lograge.custom_options = lambda do |event|
    {
      time: Time.current.iso8601,
      params: event.payload[:params].except("controller", "action", "format", "id", "authenticity_token"),
      user_id: event.payload[:user_id],
      request_id: event.payload[:request_id],
      remote_ip: event.payload[:remote_ip]
    }.compact
  end
end
