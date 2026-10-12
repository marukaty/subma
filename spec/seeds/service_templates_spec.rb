require "rails_helper"

# db/seeds/service_templates.rb の冪等性と、seed 済みテンプレートでの Tier 1 判定を検証する。
# 明細の店名はすべて架空のテストデータ。
RSpec.describe "db/seeds/service_templates.rb" do
  let(:seed_path) { Rails.root.join("db/seeds/service_templates.rb") }
  let(:deprecated_names) { [ "ahamo", "povo", "LINEMO", "楽天モバイル" ] }

  def run_seed
    expect { load seed_path }.to output.to_stdout
  end

  describe "冪等性" do
    it "2 回実行してもテンプレートが重複しない" do
      run_seed
      first_count = ServiceTemplate.count
      run_seed
      expect(ServiceTemplate.count).to eq(first_count)
      expect(ServiceTemplate.group(:service_name).having("COUNT(*) > 1").count).to be_empty
    end

    it "2 回目の実行で既存テンプレートの内容が seed の値に更新される" do
      run_seed
      ServiceTemplate.find_by!(service_name: "Adobe Creative Cloud").update!(match_patterns: [ "OLD" ])
      run_seed
      expect(ServiceTemplate.find_by!(service_name: "Adobe Creative Cloud").match_patterns).to eq([ "ADOBE", "アドビ" ])
    end
  end

  describe "廃止テンプレート（通信費。ADR-0008）" do
    it "seed に含まれない" do
      run_seed
      expect(ServiceTemplate.where(service_name: deprecated_names)).to be_empty
      expect(ServiceTemplate.where(default_category: "通信")).to be_empty
    end

    it "既存 DB に残っていた廃止テンプレートを削除する" do
      deprecated_names.each do |name|
        ServiceTemplate.create!(service_name: name, default_billing_cycle: :monthly, default_category: "通信", match_patterns: [ name ])
      end
      run_seed
      expect(ServiceTemplate.where(service_name: deprecated_names)).to be_empty
    end

    it "ユーザーが登録済みの同名サブスクには影響しない" do
      user = User.create!(firebase_uid: "uid_seed", email: "seed@example.com")
      ServiceTemplate.create!(service_name: "ahamo", default_billing_cycle: :monthly, default_category: "通信", match_patterns: [ "AHAMO" ])
      subscription = user.subscriptions.create!(service_name: "ahamo", amount: 2970, billing_cycle: :monthly, category: "通信")
      run_seed
      expect(Subscription.find(subscription.id).service_name).to eq("ahamo")
    end
  end

  describe "seed 済みテンプレートでの Tier 1（RuleClassifier）判定" do
    before { run_seed }

    let(:classifier) { Classifiers::RuleClassifier.new }

    def classify(description)
      row = { date: Date.new(2026, 4, 1), description: description, amount: BigDecimal("1000") }
      classifier.classify([ row ]).classified.first&.dig(:inferred_service_name)
    end

    it "半角カナの店名を正規化して一致させる" do
      expect(classify("ｱﾄﾞﾋﾞｶﾌﾞｼｷｶﾞｲｼｬ")).to eq("Adobe Creative Cloud")
      expect(classify("ﾌﾟﾛｹﾞｰﾄ")).to eq("Progate")
    end

    it "全角英字の店名を正規化して一致させる" do
      expect(classify("ＮＥＴＦＬＩＸ．ＣＯＭ")).to eq("Netflix")
    end

    it "既存の一致は壊れない" do
      expect(classify("NETFLIX.COM")).to eq("Netflix")
      expect(classify("ネットフリックス")).to eq("Netflix")
      expect(classify("ADOBE *CREATIVE CLD")).to eq("Adobe Creative Cloud")
      expect(classify("PROGATE INC")).to eq("Progate")
      expect(classify("AMAZON PRIME MEMBERSHIP")).to eq("Amazon Prime")
      expect(classify("AWS EMEA")).to eq("AWS")
    end

    it "Apple の汎用課金は Apple（App Store/iCloud）、個別表記は個別サービスに一致する" do
      expect(classify("APPLE COM BILL")).to eq("Apple（App Store/iCloud）")
      expect(classify("APPLE.COM/BILL")).to eq("Apple（App Store/iCloud）")
      expect(classify("APPLE.COM/BILL MUSIC")).to eq("Apple Music")
      expect(classify("APPLE.COM/BILL TV")).to eq("Apple TV+")
    end

    it "通信費はルールでは一致しない" do
      expect(classify("楽天モバイル通信料")).to be_nil
      expect(classify("日本通信株式会社")).to be_nil
      expect(classify("ﾗｸﾃﾝﾓﾊﾞｲﾙ")).to be_nil
    end

    it "通常の買い物・コンビニは一致しない" do
      expect(classify("AMAZON.CO.JP")).to be_nil
      expect(classify("LAWSON")).to be_nil
    end
  end
end
