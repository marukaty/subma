# Phase 1 Task 2 で本格設定する。現状は最小構成（Phase 1 Task 1 が動くこと優先）
# Firebase Auth は Google アカウントポップアップを使うため、CSP の対応も Task 2 で詰める

SecureHeaders::Configuration.default do |config|
  config.x_frame_options = "DENY"
  config.x_content_type_options = "nosniff"
  config.x_xss_protection = "0"
  config.referrer_policy = %w[strict-origin-when-cross-origin]
  config.hsts = "max-age=31536000; includeSubDomains"

  # CSP は Firebase の動作（apis.google.com / accounts.google.com / *.firebaseapp.com）が必要
  # Phase 1 Task 2 で厳密化、現状は緩めの初期値
  config.csp = {
    default_src: %w['self'],
    script_src: %w['self' 'unsafe-inline' https://*.googleapis.com https://*.google.com https://*.gstatic.com https://accounts.google.com],
    connect_src: %w['self' https://*.googleapis.com https://*.google.com https://securetoken.googleapis.com https://identitytoolkit.googleapis.com https://*.firebaseio.com wss://*.firebaseio.com],
    img_src: %w['self' data: https://*.googleusercontent.com https://lh3.googleusercontent.com],
    style_src: %w['self' 'unsafe-inline' https://*.googleapis.com https://fonts.googleapis.com],
    font_src: %w['self' https://fonts.gstatic.com],
    frame_src: %w['self' https://*.firebaseapp.com https://accounts.google.com],
    base_uri: %w['self'],
    form_action: %w['self']
  }
end
