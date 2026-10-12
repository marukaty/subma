# ログインの許可リスト判定（招待制）。
#
# ログインを通す条件（すべて満たす必要がある）:
#   1. ID トークンの email_verified が true
#   2. ID トークンの firebase.sign_in_provider が "google.com"
#   3. メールアドレスが環境変数 ALLOWED_LOGIN_EMAILS（カンマ区切り）に含まれる
#      （比較は前後の空白を除き、大文字小文字を区別しない）
#
# fail-closed:
#   - ALLOWED_LOGIN_EMAILS が未設定・空の場合は、全環境で全員を拒否する
#   - "*" は development / test（Rails.env.local?）でだけ「全員許可」として扱う。
#     production では "*" を無視する（設定ミスで全員に開放されるのを防ぐ）
#
# 環境変数は呼び出しのたびに読む（キャッシュしない）。
# ApplicationController#current_user から毎リクエスト呼ばれ、許可を外したユーザーを締め出す。
#
# 詳細: docs/adr/0006-login-allowlist.md
#
# [ai-assisted]
class LoginAllowlist
  ENV_KEY = "ALLOWED_LOGIN_EMAILS".freeze
  WILDCARD = "*".freeze
  REQUIRED_SIGN_IN_PROVIDER = "google.com".freeze

  # 拒否理由
  REASON_EMAIL_NOT_VERIFIED = :email_not_verified
  REASON_PROVIDER_NOT_ALLOWED = :provider_not_allowed
  REASON_EMAIL_NOT_LISTED = :email_not_listed

  Decision = Struct.new(:allowed, :reason) do
    def allowed?
      allowed
    end
  end

  class << self
    # ID トークンの検証済みクレームでログイン可否を判定する
    # @param claims [Hash] FirebaseAuthVerifier#verify の戻り値
    # @return [Decision]
    def check(claims)
      claims = (claims || {}).to_h.with_indifferent_access

      return deny(REASON_EMAIL_NOT_VERIFIED) unless claims[:email_verified] == true
      return deny(REASON_PROVIDER_NOT_ALLOWED) unless claims.dig(:firebase, :sign_in_provider) == REQUIRED_SIGN_IN_PROVIDER
      return deny(REASON_EMAIL_NOT_LISTED) unless allowed_email?(claims[:email])

      Decision.new(true, nil)
    end

    # @param claims [Hash]
    # @return [Boolean]
    def allowed?(claims)
      check(claims).allowed?
    end

    # メールアドレスが許可リストに含まれるか（毎リクエストの再判定でも使う）
    # @param email [String, nil]
    # @return [Boolean]
    def allowed_email?(email)
      normalized = normalize(email)
      return false if normalized.blank?

      entries = allowed_entries
      return false if entries.empty?
      return true if entries.include?(WILDCARD) && wildcard_permitted?

      entries.include?(normalized)
    end

    # ログ出力用にメールアドレスをマスクする（先頭 2 文字 + ドメイン）
    # 例: "alice@example.com" -> "al***@example.com"
    # @param email [String, nil]
    # @return [String]
    def mask_email(email)
      normalized = normalize(email)
      return "(none)" if normalized.blank?

      local, domain = normalized.split("@", 2)
      return "***" if domain.blank?

      "#{local.first(2)}***@#{domain}"
    end

    private

    def deny(reason)
      Decision.new(false, reason)
    end

    def normalize(email)
      email.to_s.strip.downcase
    end

    def allowed_entries
      ENV.fetch(ENV_KEY, "").split(",").map { |entry| normalize(entry) }.reject(&:blank?)
    end

    def wildcard_permitted?
      Rails.env.local?
    end
  end
end
