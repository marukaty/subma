require "rails_helper"

RSpec.describe Transaction, type: :model do
  let(:user) { User.create!(firebase_uid: "uid_tx", email: "tx@example.com") }
  let(:csv_import) do
    CsvImport.create!(user: user, filename: "x.csv", format: :rakuten, status: :uploading)
  end
  let(:valid_attrs) do
    {
      csv_import: csv_import,
      user: user,
      transaction_date: Date.new(2026, 4, 1),
      amount: 1490,
      description: "NETFLIX.COM",
      classification: :unknown
    }
  end

  describe "validations" do
    it { expect(described_class.new(valid_attrs)).to be_valid }
    it { expect(described_class.new(valid_attrs.merge(transaction_date: nil))).not_to be_valid }
    it { expect(described_class.new(valid_attrs.merge(amount: nil))).not_to be_valid }
    it { expect(described_class.new(valid_attrs.merge(description: ""))).not_to be_valid }

    it "rejects confidence > 1" do
      expect(described_class.new(valid_attrs.merge(confidence: 1.1))).not_to be_valid
    end

    it "allows confidence in [0, 1]" do
      expect(described_class.new(valid_attrs.merge(confidence: 0.85))).to be_valid
    end

    it "allows nil confidence" do
      expect(described_class.new(valid_attrs.merge(confidence: nil))).to be_valid
    end
  end

  describe "enums" do
    it "classification values" do
      expect(described_class.classifications.keys).to match_array(%w[unknown subscription non_subscription])
    end

    it "classifier values" do
      expect(described_class.classifiers.keys).to match_array(%w[rule pattern ai user])
    end
  end

  describe "scopes" do
    it ".for_review returns subscription-classified records" do
      _unknown_tx = described_class.create!(valid_attrs.merge(classification: :unknown))
      sub_tx = described_class.create!(valid_attrs.merge(classification: :subscription, description: "Sub"))
      _non_tx = described_class.create!(valid_attrs.merge(classification: :non_subscription, description: "Non"))

      expect(described_class.for_review).to contain_exactly(sub_tx)
    end
  end
end
