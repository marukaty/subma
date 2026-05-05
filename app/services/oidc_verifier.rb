# Google OIDC ID トークンを検証する。
# Cloud Tasks / Cloud Scheduler / Cloud Run の HTTP push 経由で送られてくる
# Authorization: Bearer <id_token> を受信側で検証する用途で使う。
#
# 検証項目（Google "Verifying the integrity of OIDC tokens" 準拠）:
#   - 署名: RS256, Google の公開証明書（kid に対応）で検証
#   - aud: 期待する受信 URL と一致（initialize 時に audience: で指定）
#   - iss: "https://accounts.google.com" または "accounts.google.com" と一致
#   - exp: 未来（JWT gem が自動検証）
#
# 公開証明書は最大 1 時間 Rails.cache にキャッシュする
# （HTTP の Cache-Control に従うのが理想だが、シンプルさを優先して固定 TTL）。
#
# 例外:
#   - InvalidTokenError: 検証失敗（呼び出し側は 401 を返す想定）
#
# 設計判断:
#   - FirebaseAuthVerifier と意図的に同じパターン（v1 X509 形式の certs を使う）。
#     v3 JWK 形式に揃える選択肢もあるが、既存コードと統一した方が保守性が高い。
#   - kid・iss・aud・exp の検証は JWT gem に委譲し、独自実装はしない。
#
# [ai-assisted]
class OidcVerifier
  CERTS_URL = "https://www.googleapis.com/oauth2/v1/certs".freeze
  CERTS_CACHE_KEY = "oidc_verifier:public_certs".freeze
  CERTS_CACHE_TTL = 1.hour
  ALGORITHM = "RS256".freeze
  VALID_ISSUERS = [ "https://accounts.google.com", "accounts.google.com" ].freeze

  class InvalidTokenError < StandardError; end

  # @param audience [String] 期待する OIDC aud クレーム（受信側 URL）
  def initialize(audience:)
    raise ArgumentError, "audience is required" if audience.blank?

    @audience = audience
  end

  # @param id_token [String] OIDC ID トークン
  # @return [Hash] 検証済みクレーム（"sub", "email", "iss", "aud", "exp" 等を含む）
  def verify(id_token)
    raise InvalidTokenError, "token is blank" if id_token.blank?

    unverified_header = JWT.decode(id_token, nil, false).last
    kid = unverified_header["kid"]
    raise InvalidTokenError, "missing kid in token header" if kid.blank?

    cert_pem = fetch_certs[kid]
    raise InvalidTokenError, "unknown kid: #{kid}" if cert_pem.blank?

    public_key = OpenSSL::X509::Certificate.new(cert_pem).public_key

    decoded, = JWT.decode(
      id_token,
      public_key,
      true,
      {
        algorithm: ALGORITHM,
        verify_iss: true,
        iss: VALID_ISSUERS,
        verify_aud: true,
        aud: @audience
      }
    )

    decoded
  rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature,
         JWT::InvalidIssuerError, JWT::InvalidAudError,
         OpenSSL::X509::CertificateError => e
    raise InvalidTokenError, e.message
  end

  private

  def fetch_certs
    Rails.cache.fetch(CERTS_CACHE_KEY, expires_in: CERTS_CACHE_TTL) do
      response = Net::HTTP.get_response(URI(CERTS_URL))
      raise InvalidTokenError, "failed to fetch certs: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end
  end
end
