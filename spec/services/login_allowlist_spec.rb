require "rails_helper"

RSpec.describe LoginAllowlist do
  let(:claims) do
    {
      "sub" => "uid_allowed",
      "email" => "alice@example.com",
      "email_verified" => true,
      "firebase" => { "sign_in_provider" => "google.com" }
    }
  end

  before { with_allowed_login_emails("alice@example.com,bob@example.org") }

  describe ".check" do
    it "allows a verified Google account on the list" do
      decision = described_class.check(claims)
      expect(decision).to be_allowed
      expect(decision.reason).to be_nil
    end

    it "accepts symbol keys" do
      expect(described_class.allowed?(claims.deep_symbolize_keys)).to be(true)
    end

    it "denies when email_verified is false" do
      decision = described_class.check(claims.merge("email_verified" => false))
      expect(decision).not_to be_allowed
      expect(decision.reason).to eq(:email_not_verified)
    end

    it "denies when email_verified is missing or not strictly true" do
      expect(described_class.check(claims.except("email_verified")).reason).to eq(:email_not_verified)
      expect(described_class.check(claims.merge("email_verified" => "true")).reason).to eq(:email_not_verified)
    end

    it "denies providers other than google.com" do
      %w[password anonymous github.com].each do |provider|
        decision = described_class.check(claims.merge("firebase" => { "sign_in_provider" => provider }))
        expect(decision.reason).to eq(:provider_not_allowed), "expected #{provider} to be denied"
      end
    end

    it "denies when the firebase claim is missing" do
      expect(described_class.check(claims.except("firebase")).reason).to eq(:provider_not_allowed)
    end

    it "denies an email that is not on the list" do
      decision = described_class.check(claims.merge("email" => "mallory@example.com"))
      expect(decision.reason).to eq(:email_not_listed)
    end

    it "denies a token without email" do
      expect(described_class.check(claims.except("email")).reason).to eq(:email_not_listed)
    end

    it "denies nil claims" do
      expect(described_class.check(nil)).not_to be_allowed
    end
  end

  describe ".allowed_email?" do
    it "normalizes case and surrounding whitespace on both sides" do
      with_allowed_login_emails("  Alice@Example.COM ,\tbob@example.org  ")
      expect(described_class.allowed_email?("alice@example.com")).to be(true)
      expect(described_class.allowed_email?("  ALICE@example.com ")).to be(true)
      expect(described_class.allowed_email?("Bob@Example.org")).to be(true)
    end

    it "does not match partial addresses" do
      expect(described_class.allowed_email?("lice@example.com")).to be(false)
      expect(described_class.allowed_email?("alice@example.co")).to be(false)
    end

    it "ignores empty entries" do
      with_allowed_login_emails(",, ,alice@example.com,")
      expect(described_class.allowed_email?("alice@example.com")).to be(true)
      expect(described_class.allowed_email?("")).to be(false)
    end

    it "denies blank emails" do
      expect(described_class.allowed_email?(nil)).to be(false)
      expect(described_class.allowed_email?("  ")).to be(false)
    end

    context "when the list is empty (fail-closed)" do
      it "denies everyone when unset" do
        ENV.delete(LoginAllowlist::ENV_KEY)
        expect(described_class.allowed_email?("alice@example.com")).to be(false)
        expect(described_class.allowed?(claims)).to be(false)
      end

      it "denies everyone when empty or whitespace only" do
        [ "", "   ", " , , " ].each do |value|
          with_allowed_login_emails(value)
          expect(described_class.allowed_email?("alice@example.com")).to be(false)
        end
      end

      it "denies everyone in production as well" do
        ENV.delete(LoginAllowlist::ENV_KEY)
        allow(Rails.env).to receive(:local?).and_return(false)
        expect(described_class.allowed_email?("alice@example.com")).to be(false)
      end
    end

    context "with the wildcard" do
      before { with_allowed_login_emails("*") }

      it "allows any email in development/test" do
        expect(described_class.allowed_email?("anyone@example.net")).to be(true)
      end

      it "ignores the wildcard in production" do
        allow(Rails.env).to receive(:local?).and_return(false)
        expect(described_class.allowed_email?("anyone@example.net")).to be(false)
      end

      it "still honors explicit entries next to the wildcard in production" do
        with_allowed_login_emails("*,alice@example.com")
        allow(Rails.env).to receive(:local?).and_return(false)
        expect(described_class.allowed_email?("alice@example.com")).to be(true)
        expect(described_class.allowed_email?("anyone@example.net")).to be(false)
      end

      it "still requires email_verified and the Google provider" do
        expect(described_class.check(claims.merge("email_verified" => false))).not_to be_allowed
        expect(described_class.check(claims.merge("firebase" => { "sign_in_provider" => "password" }))).not_to be_allowed
      end
    end
  end

  describe ".mask_email" do
    it "keeps the first two characters and the domain" do
      expect(described_class.mask_email("Alice@Example.com")).to eq("al***@example.com")
    end

    it "handles short local parts, missing domains and blanks" do
      expect(described_class.mask_email("a@example.com")).to eq("a***@example.com")
      expect(described_class.mask_email("not-an-email")).to eq("***")
      expect(described_class.mask_email(nil)).to eq("(none)")
    end
  end
end
