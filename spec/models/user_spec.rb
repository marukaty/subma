require "rails_helper"

RSpec.describe User, type: :model do
  describe "validations" do
    subject { described_class.new(firebase_uid: "uid_abc", email: "test@example.com") }

    it { is_expected.to be_valid }

    it "requires firebase_uid" do
      subject.firebase_uid = nil
      expect(subject).not_to be_valid
    end

    it "requires email" do
      subject.email = nil
      expect(subject).not_to be_valid
    end

    it "rejects duplicated firebase_uid" do
      described_class.create!(firebase_uid: "uid_dup", email: "a@example.com")
      duplicate = described_class.new(firebase_uid: "uid_dup", email: "b@example.com")
      expect(duplicate).not_to be_valid
    end
  end

  describe ".from_firebase_claims" do
    let(:claims) do
      {
        "sub" => "uid_xyz",
        "email" => "tanaka@example.com",
        "name" => "Tanaka Taro"
      }
    end

    it "creates a new user when none exists" do
      expect { described_class.from_firebase_claims(claims) }.to change(described_class, :count).by(1)
    end

    it "sets attributes from claims" do
      user = described_class.from_firebase_claims(claims)
      expect(user.firebase_uid).to eq("uid_xyz")
      expect(user.email).to eq("tanaka@example.com")
      expect(user.display_name).to eq("Tanaka Taro")
      expect(user.notification_enabled).to be(true)
    end

    it "is idempotent: looks up existing user by firebase_uid" do
      first = described_class.from_firebase_claims(claims)
      second = described_class.from_firebase_claims(claims)
      expect(second.id).to eq(first.id)
    end

    it "updates email and name on subsequent calls" do
      described_class.from_firebase_claims(claims)
      updated = described_class.from_firebase_claims(claims.merge("email" => "new@example.com", "name" => "New Name"))
      expect(updated.email).to eq("new@example.com")
      expect(updated.display_name).to eq("New Name")
    end

    it "falls back to email local-part when name claim is absent" do
      user = described_class.from_firebase_claims(claims.except("name"))
      expect(user.display_name).to eq("tanaka")
    end

    it "raises when sub claim is missing" do
      expect { described_class.from_firebase_claims(claims.except("sub")) }.to raise_error(ArgumentError, /missing sub/)
    end
  end
end
