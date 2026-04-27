require "rails_helper"

RSpec.describe CsvImport, type: :model do
  let(:user) { User.create!(firebase_uid: "uid_csv", email: "csv@example.com") }
  let(:valid_attrs) { { user: user, filename: "rakuten_2026_04.csv", format: :rakuten, status: :uploading } }

  describe "validations" do
    it { expect(described_class.new(valid_attrs)).to be_valid }
    it { expect(described_class.new(valid_attrs.merge(filename: nil))).not_to be_valid }
    it { expect(described_class.new(valid_attrs.merge(format: nil))).not_to be_valid }
  end

  describe "enums" do
    it "supports format values" do
      expect(described_class.formats.keys).to match_array(%w[rakuten smcc jcb aeon mufg generic])
    end

    it "supports status values" do
      expect(described_class.statuses.keys).to match_array(
        %w[uploading processing rule_matching ai_analyzing completed failed]
      )
    end
  end

  describe "associations" do
    it "destroys related transactions" do
      ci = described_class.create!(valid_attrs)
      ci.transactions.create!(
        user: user,
        transaction_date: Date.current,
        amount: 1490,
        description: "NETFLIX",
        classification: :unknown
      )
      expect { ci.destroy }.to change(Transaction, :count).by(-1)
    end
  end

  describe "#purge_uploaded_file!" do
    it "no-op when no file attached" do
      ci = described_class.create!(valid_attrs)
      expect { ci.purge_uploaded_file! }.not_to raise_error
    end

    it "purges attached file" do
      ci = described_class.create!(valid_attrs)
      ci.file.attach(
        io: StringIO.new("dummy"),
        filename: "test.csv",
        content_type: "text/csv"
      )
      expect(ci.file).to be_attached
      ci.purge_uploaded_file!
      expect(ci.reload.file).not_to be_attached
    end
  end
end
