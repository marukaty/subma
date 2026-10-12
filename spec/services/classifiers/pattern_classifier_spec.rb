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
    around do |example|
      travel_to(Time.zone.local(2026, 10, 20, 12, 0, 0)) { example.run }
    end

    let(:desc) { "MONTHLY SVC" }
    let(:amount) { BigDecimal("980") }

    def row_on(date, description: desc, amount: self.amount)
      { date: date, description: description, amount: amount }
    end

    def history_on(date, description: desc, amount: self.amount)
      make_history_tx(description: description, amount: amount, transaction_date: date)
    end

    def classify(rows, **opts)
      described_class.new(user: user, **opts).classify(rows)
    end

    it "marks the row with classifier pattern and confidence 0.7" do
      history_on(Date.new(2026, 9, 5))

      result = classify([ row_on(Date.new(2026, 10, 5)) ])

      expect(result.classified.size).to eq(1)
      expect(result.classified.first[:classification]).to eq("subscription")
      expect(result.classified.first[:classifier]).to eq("pattern")
      expect(result.classified.first[:confidence]).to eq(0.7)
    end

    it "leaves rows without a matching pair in unclassified" do
      history_on(Date.new(2026, 10, 1))

      result = classify([ row_on(Date.new(2026, 10, 15)) ])

      expect(result.classified).to be_empty
      expect(result.unclassified.size).to eq(1)
    end

    context "履歴との間隔（月額相当: 25〜35 日）" do
      let(:row_date) { Date.new(2026, 10, 15) }

      {
        30 => true,
        28 => true,
        25 => true,
        35 => true,
        36 => false,
        24 => false
      }.each do |days, expected|
        it "#{days} 日差 → #{expected ? '候補になる' : '候補にならない'}" do
          history_on(row_date - days)

          result = classify([ row_on(row_date) ])
          expect(result.classified.size).to eq(expected ? 1 : 0)
        end
      end

      it "同日の履歴だけ（再取り込みの重複）→ 候補にならない" do
        history_on(row_date)
        history_on(row_date)

        result = classify([ row_on(row_date) ])
        expect(result.classified).to be_empty
      end

      it "同月内の 3 日差（偶然の同額）→ 候補にならない" do
        rows = [ row_on(Date.new(2026, 8, 9)), row_on(Date.new(2026, 8, 12)) ]
        rows.each { |r| history_on(r[:date]) }

        result = classify(rows)
        expect(result.classified).to be_empty
        expect(result.unclassified.size).to eq(2)
      end

      it "9/30 と 10/2（別の月だが 2 日差）→ 候補にならない" do
        history_on(Date.new(2026, 9, 30))

        result = classify([ row_on(Date.new(2026, 10, 2)) ])
        expect(result.classified).to be_empty
      end

      it "履歴 8/15 と今回 9/15 → 候補になる" do
        history_on(Date.new(2026, 8, 15))

        result = classify([ row_on(Date.new(2026, 9, 15)) ])
        expect(result.classified.size).to eq(1)
      end

      it "店名や金額が違う履歴とはペアにならない" do
        history_on(Date.new(2026, 9, 15), amount: BigDecimal("1080"))
        history_on(Date.new(2026, 9, 15), description: "OTHER SVC")

        result = classify([ row_on(Date.new(2026, 10, 15)) ])
        expect(result.classified).to be_empty
      end
    end

    context "履歴との間隔（年額相当: 360〜370 日）" do
      it "365 日差 → 候補になる" do
        history_on(Date.new(2025, 10, 10))

        result = classify([ row_on(Date.new(2026, 10, 10)) ])
        expect(result.classified.size).to eq(1)
      end

      it "371 日差 → 候補にならない" do
        history_on(Date.new(2026, 10, 10) - 371)

        result = classify([ row_on(Date.new(2026, 10, 10)) ])
        expect(result.classified).to be_empty
      end
    end

    context "取り込み中の CSV 内の行同士" do
      it "9/15 と 10/15 の同店名・同額 → 両方候補になる（履歴なし）" do
        rows = [ row_on(Date.new(2026, 9, 15)), row_on(Date.new(2026, 10, 15)) ]

        result = classify(rows)
        expect(result.classified.size).to eq(2)
      end

      it "同日 2 件 → 候補にならない" do
        rows = [ row_on(Date.new(2026, 9, 15)), row_on(Date.new(2026, 9, 15)) ]

        result = classify(rows)
        expect(result.classified).to be_empty
      end

      it "金額が違えば → 候補にならない" do
        rows = [ row_on(Date.new(2026, 9, 15)), row_on(Date.new(2026, 10, 15), amount: BigDecimal("1080")) ]

        result = classify(rows)
        expect(result.classified).to be_empty
      end
    end

    context "lookback の境界（2026-10-20 時点）" do
      it "月額: 既定 6 ヶ月（2026-04-20）より前の履歴は数えない" do
        history_on(Date.new(2026, 4, 19))

        result = classify([ row_on(Date.new(2026, 5, 19)) ])
        expect(result.classified).to be_empty
      end

      it "月額: 境界ちょうど（2026-04-20）の履歴は数える" do
        history_on(Date.new(2026, 4, 20))

        result = classify([ row_on(Date.new(2026, 5, 20)) ])
        expect(result.classified.size).to eq(1)
      end

      it "月額: lookback_months を指定するとその期間に従う" do
        history_on(Date.new(2026, 6, 1))

        result = classify([ row_on(Date.new(2026, 7, 1)) ], lookback_months: 3)
        expect(result.classified).to be_empty
      end

      it "年額: 13 ヶ月（2025-09-20）以内の履歴は数える" do
        history_on(Date.new(2025, 9, 25))

        result = classify([ row_on(Date.new(2026, 9, 25)) ])
        expect(result.classified.size).to eq(1)
      end

      it "年額: 13 ヶ月より前の履歴は数えない" do
        history_on(Date.new(2025, 9, 15))

        result = classify([ row_on(Date.new(2026, 9, 15)) ])
        expect(result.classified).to be_empty
      end
    end

    it "isolates per user (other users' history doesn't count)" do
      other = User.create!(firebase_uid: "uid_other_p", email: "o@example.com")
      ci = CsvImport.create!(user: other, filename: "other.csv", format: :rakuten, status: :completed)
      Transaction.create!(csv_import: ci, user: other, transaction_date: Date.new(2026, 9, 15), amount: 100, description: "SHARED", classification: :unknown)

      result = classify([ row_on(Date.new(2026, 10, 15), description: "SHARED", amount: BigDecimal("100")) ])
      expect(result.classified).to be_empty
    end
  end
end
