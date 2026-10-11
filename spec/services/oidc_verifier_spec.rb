require "rails_helper"

RSpec.describe OidcVerifier do
  let(:audience) { "https://subma.example.com/internal/jobs/process_csv" }
  let(:expected_email) { "tasks@subma-test.iam.gserviceaccount.com" }
  let(:verifier) { described_class.new(audience: audience, expected_email: expected_email) }
  let(:rsa_private) { OpenSSL::PKey::RSA.new(2048) }
  let(:kid) { "test-oidc-kid" }
  let(:cert_pem) { build_self_signed_cert_pem(rsa_private) }
  let(:certs_response) { { kid => cert_pem } }
  let(:base_payload) do
    now = Time.now.to_i
    {
      "iss" => "https://accounts.google.com",
      "aud" => audience,
      "iat" => now - 60,
      "exp" => now + 600,
      "sub" => "12345",
      "email" => "tasks@subma-test.iam.gserviceaccount.com",
      "email_verified" => true
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
    cert.subject = OpenSSL::X509::Name.parse("/CN=test-oidc")
    cert.issuer = cert.subject
    cert.public_key = key.public_key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + 3600
    cert.sign(key, OpenSSL::Digest.new("SHA256"))
    cert.to_pem
  end

  describe "#verify" do
    it "returns claims for a valid token" do
      claims = verifier.verify(encode_token(base_payload))
      expect(claims["sub"]).to eq("12345")
      expect(claims["email"]).to eq("tasks@subma-test.iam.gserviceaccount.com")
    end

    it "accepts both 'https://accounts.google.com' and 'accounts.google.com' as iss" do
      bare_iss = encode_token(base_payload.merge("iss" => "accounts.google.com"))
      claims = verifier.verify(bare_iss)
      expect(claims["iss"]).to eq("accounts.google.com")
    end

    it "rejects blank token" do
      expect { verifier.verify("") }
        .to raise_error(described_class::InvalidTokenError, /blank/)
    end

    it "rejects token with wrong audience" do
      bad = encode_token(base_payload.merge("aud" => "https://other.example.com/foo"))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token with wrong issuer" do
      bad = encode_token(base_payload.merge("iss" => "https://attacker.example.com"))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects expired token" do
      bad = encode_token(base_payload.merge("exp" => Time.now.to_i - 60))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token signed by an unknown key" do
      other_key = OpenSSL::PKey::RSA.new(2048)
      bad = JWT.encode(base_payload, other_key, "RS256", { "kid" => kid })
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError)
    end

    it "rejects token issued by a different service account" do
      bad = encode_token(base_payload.merge("email" => "attacker@other-project.iam.gserviceaccount.com"))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /unexpected token email/)
    end

    it "rejects token without email claim" do
      bad = encode_token(base_payload.except("email"))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /unexpected token email/)
    end

    it "rejects token with email_verified false" do
      bad = encode_token(base_payload.merge("email_verified" => false))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /email_verified/)
    end

    it "rejects token with email_verified given as a string" do
      bad = encode_token(base_payload.merge("email_verified" => "true"))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /email_verified/)
    end

    it "rejects token without email_verified claim" do
      bad = encode_token(base_payload.except("email_verified"))
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /email_verified/)
    end

    it "rejects token with unknown kid" do
      bad = JWT.encode(base_payload, rsa_private, "RS256", { "kid" => "unknown-kid" })
      expect { verifier.verify(bad) }
        .to raise_error(described_class::InvalidTokenError, /unknown kid/)
    end
  end

  describe "constructor" do
    it "raises when audience missing" do
      expect { described_class.new(audience: nil, expected_email: expected_email) }.to raise_error(ArgumentError)
    end

    it "raises when expected_email missing (fail-closed)" do
      expect { described_class.new(audience: audience, expected_email: nil) }.to raise_error(ArgumentError)
      expect { described_class.new(audience: audience, expected_email: "") }.to raise_error(ArgumentError)
    end
  end
end
