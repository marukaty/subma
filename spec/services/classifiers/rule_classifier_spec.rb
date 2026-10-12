require "rails_helper"

RSpec.describe Classifiers::RuleClassifier do
  let(:netflix_template) do
    ServiceTemplate.create!(
      service_name: "TestNetflix",
      default_amount: 1490,
      default_billing_cycle: :monthly,
      default_category: "エンタメ",
      match_patterns: [ "NETFLIX", "ネットフリックス" ]
    )
  end

  let(:rows) do
    [
      { date: Date.new(2026, 4, 1), description: "NETFLIX.COM", amount: BigDecimal("1490") },
      { date: Date.new(2026, 4, 5), description: "ENEOS XXX", amount: BigDecimal("5500") },
      { date: Date.new(2026, 4, 10), description: "ネットフリックス", amount: BigDecimal("1490") }
    ]
  end

  describe "#classify" do
    it "matches via regex (case-insensitive)" do
      result = described_class.new(templates: [ netflix_template ]).classify(rows)
      expect(result.classified.size).to eq(2)
      expect(result.unclassified.size).to eq(1)
      expect(result.classified.first[:inferred_service_name]).to eq("TestNetflix")
      expect(result.classified.first[:classifier]).to eq("rule")
      expect(result.classified.first[:confidence]).to eq(1.0)
    end

    it "leaves unmatched rows in unclassified" do
      result = described_class.new(templates: [ netflix_template ]).classify(rows)
      expect(result.unclassified.first[:description]).to eq("ENEOS XXX")
    end

    it "半角カナ・全角英字の店名も正規化して一致させる" do
      kana_rows = [
        { date: Date.new(2026, 4, 1), description: "ﾈｯﾄﾌﾘｯｸｽ", amount: BigDecimal("1490") },
        { date: Date.new(2026, 4, 2), description: "ＮＥＴＦＬＩＸ", amount: BigDecimal("1490") }
      ]
      result = described_class.new(templates: [ netflix_template ]).classify(kana_rows)
      expect(result.classified.size).to eq(2)
      expect(result.unclassified).to be_empty
    end

    it "複数のテンプレートに一致する場合は先頭（id 昇順）のものを採用する" do
      specific = ServiceTemplate.create!(service_name: "TestAppleMusic", default_billing_cycle: :monthly, match_patterns: [ "APPLE.*MUSIC" ])
      generic = ServiceTemplate.create!(service_name: "TestAppleGeneric", default_billing_cycle: :monthly, match_patterns: [ "APPLE\\.COM/BILL" ])
      row = { date: Date.new(2026, 4, 1), description: "APPLE.COM/BILL MUSIC", amount: BigDecimal("1080") }

      result = described_class.new(templates: ServiceTemplate.where(id: [ generic.id, specific.id ]).order(:id).to_a).classify([ row ])
      expect(result.classified.first[:inferred_service_name]).to eq("TestAppleMusic")
    end

    it "returns empty classified when templates is empty" do
      result = described_class.new(templates: []).classify(rows)
      expect(result.classified).to be_empty
      expect(result.unclassified.size).to eq(3)
    end
  end
end
