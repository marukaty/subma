# Firebase の ID トークン（JWT）を検証する。
# Admin SDK を使わず、Firebase の公開証明書を取得して RS256 署名を検証する。
#
# 検証項目（Firebase 公式ドキュメント "Verify ID Tokens" 準拠）:
#   - 署名: RS256, Firebase の公開証明書（kid に対応）で検証
#   - aud: FIREBASE_PROJECT_ID と一致
#   - iss: "https://securetoken.google.com/<FIREBASE_PROJECT_ID>" と一致
#   - exp: 未来
#   - iat: 過去
#   - sub: 非空
#
# 公開証明書は最大 1 時間 Rails.cache にキャッシュする（HTTP の Cache-Control に従うのが理想だが
# シンプルさを優先して固定 TTL）。
#
# 例外:
#   - InvalidTokenError: 検証失敗（呼び出し側は 401 を返す想定）
class FirebaseAuthVerifier
  CERTS_URL = "https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com".freeze
  CERTS_CACHE_KEY = "firebase_auth_verifier:public_certs".freeze
  CERTS_CACHE_TTL = 1.hour
  ALGORITHM = "RS256".freeze

  class InvalidTokenError < StandardError; end

  # @param project_id [String] Firebase プロジェクト ID（既定: ENV["FIREBASE_PROJECT_ID"]）
  def initialize(project_id: ENV["FIREBASE_PROJECT_ID"])
    raise ArgumentError, "project_id is required" if project_id.blank?

    @project_id = project_id
  end

  # @param id_token [String] Firebase Web SDK が発行した ID トークン
  # @return [Hash] 検証済みクレーム（"sub", "email", "name", "exp" 等を含む）
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
        verify_iat: true,
        verify_iss: true,
        iss: "https://securetoken.google.com/#{@project_id}",
        verify_aud: true,
        aud: @project_id
      }
    )

    raise InvalidTokenError, "missing sub claim" if decoded["sub"].blank?

    decoded
  rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature,
         JWT::InvalidIssuerError, JWT::InvalidAudError, JWT::InvalidIatError,
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
