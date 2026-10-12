# 基本のセキュリティヘッダー
# CSP は Rails native (config/initializers/content_security_policy.rb) に切り出し、
# chartkick / Rails 標準ヘルパーと nonce の整合性を取れるようにしている。
# secure_headers では CSP 以外（X-Frame-Options 等）を扱う。

SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "0"
  config.referrer_policy = %w[strict-origin-when-cross-origin]
  config.hsts = "max-age=31536000; includeSubDomains"

  # CSP は Rails native に任せる
  config.csp = SecureHeaders::OPT_OUT
end
