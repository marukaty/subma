# Rack::Attack 設定（NFR-S-03）
# 認証エンドポイント・CSV アップロードエンドポイントにレート制限を掛ける
#
# 制限超過時は 429 Too Many Requests を返す。
# Redis をストア（cache）として使う前提（development.rb / production.rb で設定）
# Phase 0 段階では Rails のデフォルト memory store を使うのでテストや開発で十分機能する

class Rack::Attack
  # 制限の対象から除外（health check 等）
  safelist("allow health check") do |req|
    req.path == "/up"
  end

  # 認証エンドポイント: 同一 IP からの sign_in は 5 回 / 分
  throttle("auth sign_in by ip", limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == "/auth/sign_in" && req.post?
  end

  # CSV アップロード: 同一 IP からの POST /csv_imports は 10 回 / 5 分
  # （Phase 3 で /csv_imports エンドポイントを実装した時に活きる）
  throttle("csv upload by ip", limit: 10, period: 5.minutes) do |req|
    req.ip if req.path.start_with?("/csv_imports") && req.post?
  end

  # 全般の DDoS 緩和: 同一 IP から 60 リクエスト / 10 秒を超えたら制限
  throttle("requests by ip", limit: 60, period: 10.seconds) do |req|
    req.ip
  end

  # 制限超過時のレスポンス
  self.throttled_responder = lambda do |request|
    match_data = request.env["rack.attack.match_data"]
    now = match_data[:epoch_time]
    headers = {
      "Content-Type" => "application/json",
      "RateLimit-Limit" => match_data[:limit].to_s,
      "RateLimit-Remaining" => "0",
      "RateLimit-Reset" => (now + (match_data[:period] - now % match_data[:period])).to_s
    }
    [ 429, headers, [ { error: "rate_limited", retry_after_seconds: match_data[:period] }.to_json ] ]
  end
end

# 制限が掛かったログを記録
ActiveSupport::Notifications.subscribe("throttle.rack_attack") do |_name, _start, _finish, _id, payload|
  request = payload[:request]
  Rails.logger.warn("[rack-attack] throttled #{request.ip} on #{request.path} match=#{request.env['rack.attack.matched']}")
end
