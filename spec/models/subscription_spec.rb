require "rails_helper"

RSpec.describe Subscription, type: :model do
  let(:user) { User.create!(firebase_uid: "uid_sub", email: "sub@example.com") }

  let(:valid_attrs) do
    {
      user: user,
      service_name: "Netflix",
      amount: 1490,
      currency: "JPY",
      billing_cycle: :monthly,
      status: :active,
      source: :manual
    }
  end

  describe "validations" do
    it "is valid with required attributes" do
      expect(described_class.new(valid_attrs)).to be_valid
    end

    it "requires service_name" do
      expect(described_class.new(valid_attrs.merge(service_name: nil))).not_to be_valid
    end

    it "requires amount" do
      expect(described_class.new(valid_attrs.merge(amount: nil))).not_to be_valid
    end

    it "rejects negative amount" do
      expect(described_class.new(valid_attrs.merge(amount: -100))).not_to be_valid
    end

    it "rejects currency != 3 chars" do
      expect(described_class.new(valid_attrs.merge(currency: "JP"))).not_to be_valid
    end

    it "rejects too-long memo" do
      expect(described_class.new(valid_attrs.merge(memo: "a" * 1001))).not_to be_valid
    end
  end

  describe "enums" do
    it "supports billing_cycle values" do
      expect(described_class.billing_cycles.keys).to match_array(%w[monthly yearly weekly custom])
    end

    it "supports status values" do
      expect(described_class.statuses.keys).to match_array(%w[active paused cancelled])
    end

    it "supports source values" do
      expect(described_class.sources.keys).to match_array(%w[manual csv ai])
    end
  end

  describe "scopes" do
    let!(:active_sub)    { described_class.create!(valid_attrs.merge(service_name: "A", status: :active)) }
    let!(:paused_sub)    { described_class.create!(valid_attrs.merge(service_name: "B", status: :paused)) }
    let!(:cancelled_sub) { described_class.create!(valid_attrs.merge(service_name: "C", status: :cancelled)) }

    it ".active returns only active" do
      expect(described_class.active).to contain_exactly(active_sub)
    end

    it ".paused returns only paused" do
      expect(described_class.paused).to contain_exactly(paused_sub)
    end

    describe ".upcoming" do
      it "returns active subs with next_billing_date in the next 30 days" do
        active_sub.update!(next_billing_date: 5.days.from_now.to_date)
        far_sub = described_class.create!(valid_attrs.merge(service_name: "Far", next_billing_date: 100.days.from_now.to_date))

        expect(described_class.upcoming).to include(active_sub)
        expect(described_class.upcoming).not_to include(far_sub)
      end

      it "excludes paused/cancelled even if within window" do
        paused_sub.update!(next_billing_date: 3.days.from_now.to_date)
        expect(described_class.upcoming).not_to include(paused_sub)
      end
    end
  end

  describe "#monthly_amount" do
    it "returns amount for monthly" do
      sub = described_class.new(valid_attrs.merge(amount: 1490, billing_cycle: :monthly))
      expect(sub.monthly_amount).to eq(1490)
    end

    it "divides by 12 for yearly" do
      sub = described_class.new(valid_attrs.merge(amount: 12_000, billing_cycle: :yearly))
      expect(sub.monthly_amount).to eq(1000)
    end

    it "multiplies by 4.345 for weekly" do
      sub = described_class.new(valid_attrs.merge(amount: 100, billing_cycle: :weekly))
      expect(sub.monthly_amount).to eq(BigDecimal("434.5"))
    end
  end

  describe "#yearly_amount" do
    it "multiplies by 12 for monthly" do
      sub = described_class.new(valid_attrs.merge(amount: 1490, billing_cycle: :monthly))
      expect(sub.yearly_amount).to eq(17_880)
    end

    it "returns amount for yearly" do
      sub = described_class.new(valid_attrs.merge(amount: 12_000, billing_cycle: :yearly))
      expect(sub.yearly_amount).to eq(12_000)
    end
  end

  describe "before_save: align_status_with_cancelled_at" do
    it "active で cancelled_at が過去日なら保存時に status が cancelled に補正される" do
      sub = described_class.create!(valid_attrs.merge(status: :active, cancelled_at: 30.days.ago.to_date))
      expect(sub.status).to eq("cancelled")
    end

    it "active で cancelled_at が今日なら status が cancelled に補正される" do
      sub = described_class.create!(valid_attrs.merge(status: :active, cancelled_at: Date.current))
      expect(sub.status).to eq("cancelled")
    end

    it "active で cancelled_at が未来日なら status は active のまま（解約予約）" do
      sub = described_class.create!(valid_attrs.merge(status: :active, cancelled_at: 30.days.from_now.to_date))
      expect(sub.status).to eq("active")
    end

    it "cancelled_at が nil なら status は変更されない" do
      sub = described_class.create!(valid_attrs.merge(status: :active, cancelled_at: nil))
      expect(sub.status).to eq("active")
    end

    it "paused で cancelled_at が過去日なら cancelled に補正される" do
      sub = described_class.create!(valid_attrs.merge(status: :paused, cancelled_at: 1.day.ago.to_date))
      expect(sub.status).to eq("cancelled")
    end

    it "再 save 時にも整合性が維持される（cancelled_at 後に status を active に戻されても再補正）" do
      sub = described_class.create!(valid_attrs.merge(status: :active, cancelled_at: 30.days.ago.to_date))
      expect(sub.status).to eq("cancelled")
      sub.update!(status: :active)  # 強制的に active に
      expect(sub.reload.status).to eq("cancelled")  # before_save で再補正されている
    end
  end
end
