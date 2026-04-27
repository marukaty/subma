require "rails_helper"

RSpec.describe ServiceTemplate, type: :model do
  # seed に同名サービスがあると unique 衝突するため、テスト専用のプレフィックスを使う
  let(:valid_attrs) do
    {
      service_name: "TestService_Netflix",
      default_amount: 1490,
      default_billing_cycle: :monthly,
      default_category: "エンタメ",
      match_patterns: [ "NETFLIX", "ネットフリックス" ]
    }
  end

  describe "validations" do
    it "is valid with attributes" do
      expect(described_class.new(valid_attrs)).to be_valid
    end

    it "requires service_name" do
      expect(described_class.new(valid_attrs.merge(service_name: nil))).not_to be_valid
    end

    it "rejects duplicate service_name" do
      described_class.create!(valid_attrs)
      expect(described_class.new(valid_attrs)).not_to be_valid
    end

    it "rejects negative default_amount" do
      expect(described_class.new(valid_attrs.merge(default_amount: -1))).not_to be_valid
    end
  end

  describe "#match?" do
    let(:template) { described_class.create!(valid_attrs) }

    it "matches case-insensitively" do
      expect(template.match?("netflix.com")).to be(true)
      expect(template.match?("NETFLIX 月額")).to be(true)
    end

    it "matches Japanese pattern" do
      expect(template.match?("ネットフリックス株式会社")).to be(true)
    end

    it "returns false when no pattern matches" do
      expect(template.match?("Spotify")).to be(false)
    end

    it "handles regex special chars in pattern (e.g. AMAZON.*PRIME)" do
      template = described_class.create!(valid_attrs.merge(service_name: "TestService_Amazon", match_patterns: [ "AMAZON.*PRIME" ]))
      expect(template.match?("AMAZON WEB PRIME")).to be(true)
      expect(template.match?("AMAZON BOOKS")).to be(false)
    end

    it "is safe against invalid regex (returns false instead of raising)" do
      template = described_class.create!(valid_attrs.merge(service_name: "TestService_Bad", match_patterns: [ "[invalid" ]))
      expect(template.match?("anything")).to be(false)
    end
  end

  describe "scope by_category" do
    # seed データを混ぜてカウントせず、unique なカテゴリで分離検証
    it "filters by default_category" do
      a = described_class.create!(valid_attrs.merge(default_category: "TestCategory_X"))
      _b = described_class.create!(valid_attrs.merge(service_name: "TestService_GitHub", default_category: "TestCategory_Y"))
      expect(described_class.by_category("TestCategory_X")).to contain_exactly(a)
    end
  end
end
