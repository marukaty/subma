require "rails_helper"

RSpec.describe Classifiers::PatternClassifier do
  include ActiveSupport::Testing::TimeHelpers

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
    context "繰り返しの数え方（異なる年月で数える）" do
      around do |example|
        travel_to(Time.zone.local(2026, 10, 20, 12, 0, 0)) { example.run }
      end

      let(:row) { { date: Date.new(2026, 10, 5), description: "MONTHLY SVC", amount: BigDecimal("980") } }

      it "履歴で別々の月に 2 回あれば候補になる" do
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 8, 5))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 9, 5))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified.size).to eq(1)
      end

      it "履歴が同じ月の別日に 2 回だけなら候補にならない（偶然の同額）" do
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 8, 9))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 8, 12))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified).to be_empty
        expect(result.unclassified.size).to eq(1)
      end

      it "履歴が同じ月の同日に 2 回だけなら候補にならない" do
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 8, 9))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 8, 9))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified).to be_empty
      end

      it "取り込み中の行と同じ日付の履歴は数えない（同じファイルの再取り込み）" do
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 10, 5))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 10, 5))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified).to be_empty
      end

      it "同月 2 件のファイルを再取り込みしても候補にならない" do
        rows = [
          { date: Date.new(2026, 8, 9), description: "TOLL", amount: BigDecimal("4740") },
          { date: Date.new(2026, 8, 12), description: "TOLL", amount: BigDecimal("4740") }
        ]
        rows.each { |r| make_history_tx(description: r[:description], amount: r[:amount], transaction_date: r[:date]) }

        result = described_class.new(user: user).classify(rows)
        expect(result.classified).to be_empty
        expect(result.unclassified.size).to eq(2)
      end

      it "CSV 内で 9 月と 10 月に同店名・同金額があれば候補になる（履歴なし）" do
        rows = [
          { date: Date.new(2026, 9, 5), description: "MONTHLY SVC", amount: BigDecimal("980") },
          { date: Date.new(2026, 10, 5), description: "MONTHLY SVC", amount: BigDecimal("980") }
        ]

        result = described_class.new(user: user).classify(rows)
        expect(result.classified.size).to eq(2)
      end

      it "CSV 内で同じ月に 2 件だけなら候補にならない" do
        rows = [
          { date: Date.new(2026, 9, 9), description: "TOLL", amount: BigDecimal("4740") },
          { date: Date.new(2026, 9, 12), description: "TOLL", amount: BigDecimal("4740") }
        ]

        result = described_class.new(user: user).classify(rows)
        expect(result.classified).to be_empty
      end

      it "CSV 内で月が違っても金額が違えば候補にならない" do
        rows = [
          { date: Date.new(2026, 9, 5), description: "MONTHLY SVC", amount: BigDecimal("980") },
          { date: Date.new(2026, 10, 5), description: "MONTHLY SVC", amount: BigDecimal("1080") }
        ]

        result = described_class.new(user: user).classify(rows)
        expect(result.classified).to be_empty
      end

      it "既定の lookback（6 ヶ月）より前の履歴は数えない" do
        # 2026-10-20 の 6 ヶ月前 = 2026-04-20
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 3, 5))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 4, 19))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified).to be_empty
      end

      it "lookback 境界ちょうどの日付は数える" do
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 4, 20))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 5, 20))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified.size).to eq(1)
      end

      it "期間内 1 ヶ月 + 期間外 1 ヶ月では候補にならない" do
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 4, 19))
        make_history_tx(description: "MONTHLY SVC", amount: 980, transaction_date: Date.new(2026, 9, 5))

        result = described_class.new(user: user).classify([ row ])
        expect(result.classified).to be_empty
      end
    end
  end
end
