require "rails_helper"

RSpec.describe Classifiers::PatternClassifier do
  let(:user) { User.create!(firebase_uid: "uid_pattern", email: "p@example.com") }

  def make_history_tx(description:, amount:, transaction_date:)
    csv_import = CsvImport.create!(
      user: user, filename: "history.csv", format: :rakuten, status: :completed
    )
    Transaction.create!(
      csv_import: csv_import,
      user: user,
      transaction_date: transaction_date,
      amount: amount,
      description: description,
      classification: :unknown
    )
  end

  describe "#classify" do
    it "marks rows that recur 2+ times in past 3 months" do
      make_history_tx(description: "GYM CLUB", amount: 8000, transaction_date: 1.month.ago.to_date)
      make_history_tx(description: "GYM CLUB", amount: 8000, transaction_date: 2.months.ago.to_date)

      rows = [ { date: Date.current, description: "GYM CLUB", amount: BigDecimal("8000") } ]
      result = described_class.new(user: user).classify(rows)

      expect(result.classified.size).to eq(1)
      expect(result.classified.first[:classifier]).to eq("pattern")
      expect(result.classified.first[:confidence]).to eq(0.7)
    end

    it "leaves rows with single occurrence in unclassified" do
      make_history_tx(description: "ONE TIME", amount: 500, transaction_date: 1.month.ago.to_date)

      rows = [ { date: Date.current, description: "ONE TIME", amount: BigDecimal("500") } ]
      result = described_class.new(user: user).classify(rows)

      expect(result.classified).to be_empty
      expect(result.unclassified.size).to eq(1)
    end

    it "ignores history older than lookback months" do
      make_history_tx(description: "OLD", amount: 1000, transaction_date: 6.months.ago.to_date)
      make_history_tx(description: "OLD", amount: 1000, transaction_date: 5.months.ago.to_date)

      rows = [ { date: Date.current, description: "OLD", amount: BigDecimal("1000") } ]
      result = described_class.new(user: user, lookback_months: 3).classify(rows)

      expect(result.classified).to be_empty
    end

    it "isolates per user (other users' history doesn't count)" do
      other = User.create!(firebase_uid: "uid_other_p", email: "o@example.com")
      ci = CsvImport.create!(user: other, filename: "other.csv", format: :rakuten, status: :completed)
      Transaction.create!(csv_import: ci, user: other, transaction_date: 1.month.ago.to_date, amount: 100, description: "SHARED", classification: :unknown)
      Transaction.create!(csv_import: ci, user: other, transaction_date: 2.months.ago.to_date, amount: 100, description: "SHARED", classification: :unknown)

      rows = [ { date: Date.current, description: "SHARED", amount: BigDecimal("100") } ]
      result = described_class.new(user: user).classify(rows)
      expect(result.classified).to be_empty
    end
  end
end
