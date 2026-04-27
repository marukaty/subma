require "rails_helper"

RSpec.describe AuditLog, type: :model do
  describe "validations" do
    it "requires action" do
      log = described_class.new(action: nil)
      expect(log).not_to be_valid
    end

    it "is valid without user (for pre-auth events)" do
      log = described_class.new(action: described_class::ACTION_AUTH_SIGN_IN_FAILED)
      expect(log).to be_valid
    end

    it "is valid with user" do
      user = User.create!(firebase_uid: "uid_log", email: "log@example.com")
      log = described_class.new(action: "subscriptions.create", user: user)
      expect(log).to be_valid
    end
  end

  describe "constants" do
    it "defines auth event constants" do
      expect(described_class::ACTION_AUTH_SIGN_IN).to eq("auth.sign_in")
      expect(described_class::ACTION_AUTH_SIGN_IN_FAILED).to eq("auth.sign_in_failed")
      expect(described_class::ACTION_AUTH_SIGN_OUT).to eq("auth.sign_out")
    end
  end
end
