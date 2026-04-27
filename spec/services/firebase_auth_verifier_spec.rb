require "rails_helper"

RSpec.describe FirebaseAuthVerifier do
  let(:project_id) { "subma-test" }
  let(:rsa_private) { OpenSSL::PKey::RSA.new(2048) }
  let(:rsa_public)  { rsa_private.public_key }
  let(:kid) { "test-kid-123" }
  let(:cert_pem) { build_self_signed_cert_pem(rsa_private) }
  let(:certs_response) { { kid => cert_pem } }
  let(:base_payload) do
    now = Time.now.to_i
    {
      "iss" => "https://securetoken.google.com/#{project_id}",
      "aud" => project_id,
      "iat" => now - 60,
      "exp" => now + 600,
      "sub" => "uid_abc",
      "email" => "user@example.com",
      "name" => "User Example"
    }
  end

  before do
    Rails.cache.clear
    allow_any_instance_of(described_class).to receive(:fetch_certs).and_return(certs_response)
  end

  def encode_token(payload)
    JWT.encode(payload, rsa_private, "RS256", { "kid" => kid })
  end

  def build_self_signed_cert_pem(key)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = 1
    cert.subject = OpenSSL::X509::Name.parse("/CN=test")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end

  describe "#verify" do
    it "returns claims for a valid token" do
      claims = described_class.new(project_id: project_id).verify(encode_token(base_payload))
      expect(claims["sub"]).to eq("uid_abc")
      expect(claims["email"]).to eq("user@example.com")
    end

    it "rejects blank token" do
      expect { described_class.new(project_id: project_id).verify("") }
        .to raise_error(described_class::InvalidTokenError, /blank/)
    end

    it "rejects token with wrong audience" do
      bad = encode_token(base_payload.merge("aud" => "other-project"))
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token with wrong issuer" do
      bad = encode_token(base_payload.merge("iss" => "https://attacker.example.com"))
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects expired token" do
      bad = encode_token(base_payload.merge("exp" => Time.now.to_i - 60))
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token with future iat" do
      bad = encode_token(base_payload.merge("iat" => Time.now.to_i + 3600))
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token signed by an unknown key" do
      other_key = OpenSSL::PKey::RSA.new(2048)
      bad = JWT.encode(base_payload, other_key, "RS256", { "kid" => kid })
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token with unknown kid" do
      bad = JWT.encode(base_payload, rsa_private, "RS256", { "kid" => "unknown-kid" })
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /unknown kid/)
    end

    it "rejects token without sub claim" do
      bad = encode_token(base_payload.except("sub"))
      expect { described_class.new(project_id: project_id).verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end
  end

  describe "constructor" do
    it "raises when project_id missing" do
      expect { described_class.new(project_id: nil) }.to raise_error(ArgumentError)
    end
  end
end
