# セッション Cookie の設定
#
# - expire_after: 最後のアクセスから 12 時間で Cookie を失効させる（放置された端末の対策）
# - secure: 本番では HTTPS 接続でのみ Cookie を送る（force_ssl とあわせて二重に担保）
# - same_site: :lax で他サイトからの POST に Cookie を付けない（CSRF の緩和）
# - HttpOnly は Rails の既定で有効
Rails.application.config.session_store :cookie_store,
  key: "_subma_session",
  expire_after: 12.hours,
  secure: Rails.env.production?,
  same_site: :lax
