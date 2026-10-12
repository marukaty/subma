# Rack::Attack 設定（NFR-S-03）
# 認証エンドポイント・CSV アップロードエンドポイントにレート制限を掛ける
#
# 制限超過時は 429 Too Many Requests を返す。
# カウンタのストアは Rails.cache（環境ごとの cache_store）を使う。
#
# 接続元 IP は Rails の request.remote_ip と同じ判定で決める（Rack の req.ip は使わない）。
# Cloud Run ではコンテナから見た REMOTE_ADDR がリンクローカル（169.254.0.0/16）になり、
# 実際のクライアント IP は X-Forwarded-For に入る。Rails の remote_ip は信頼する中継
# （trusted proxies。既定で 169.254.0.0/16 などのプライベート範囲を含む）を除いた右端の IP を返すが、
# Rack の req.ip はこの範囲を信頼しないため、全利用者が同じ IP として数えられてしまう。
# X-Forwarded-For の左側に偽の値を入れられても、Google のロードバランサが右端に付ける IP が使われる。

class Rack::Attack
  # 制限のキーにするクライアント IP（ログ・監査ログの remote_ip と同じ値）
  def self.client_ip(req)
    ActionDispatch::Request.new(req.env).remote_ip
  end

  # 制限の対象から除外（health check 等）
  safelist("allow health check") do |req|
    req.path == "/up"
  end

  # 認証エンドポイント: 同一 IP からの sign_in は 5 回 / 分
  throttle("auth sign_in by ip", limit: 5, period: 60.seconds) do |req|
    client_ip(req) if req.path == "/auth/sign_in" && req.post?
  end

  # CSV アップロード: 同一 IP からの POST /csv_imports は 10 回 / 5 分
  # （取り込み・登録・再実行など /csv_imports 配下の POST の合計）
  throttle("csv upload by ip", limit: 10, period: 5.minutes) do |req|
    client_ip(req) if req.path.start_with?("/csv_imports") && req.post?
  end

  # 全般の DDoS 緩和: 同一 IP から 60 リクエスト / 10 秒を超えたら制限
  throttle("requests by ip", limit: 60, period: 10.seconds) do |req|
    client_ip(req)
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
  Rails.logger.warn("[rack-attack] throttled #{Rack::Attack.client_ip(request)} on #{request.path} match=#{request.env['rack.attack.matched']}")
end
