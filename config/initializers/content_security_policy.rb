# Rails native CSP 設定（NFR-S-04）
# Phase 1 では Firebase / Google SSO / Chartkick (esm.sh) の依存を許可
# Phase 5 で厳密化予定

Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self

    policy.script_src :self,
                      :unsafe_eval,  # chart.js が内部で使う場合あり
                      "https://*.googleapis.com",
                      "https://*.google.com",
                      "https://*.gstatic.com",
                      "https://accounts.google.com",
                      "https://cdn.jsdelivr.net",
                      "https://esm.sh"

    policy.connect_src :self,
                       "https://*.googleapis.com",
                       "https://*.google.com",
                       "https://*.gstatic.com",
                       "https://securetoken.googleapis.com",
                       "https://identitytoolkit.googleapis.com",
                       "https://*.firebaseio.com",
                       "wss://*.firebaseio.com",
                       "https://esm.sh",
                       "https://cdn.jsdelivr.net"

    policy.img_src :self, :data,
                   "https://*.googleusercontent.com",
                   "https://lh3.googleusercontent.com"

    policy.style_src :self, :unsafe_inline,
                     "https://*.googleapis.com",
                     "https://fonts.googleapis.com"

    policy.font_src :self, "https://fonts.gstatic.com"

    policy.frame_src :self,
                     "https://*.firebaseapp.com",
                     "https://accounts.google.com"

    policy.base_uri :self
    policy.form_action :self
  end

  # script-src には自動で nonce を付与（chartkick の inline script に対応）
  config.content_security_policy_nonce_generator = ->(request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]
end
