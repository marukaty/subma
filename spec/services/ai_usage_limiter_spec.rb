require "rails_helper"

RSpec.describe AiUsageLimiter do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { User.create!(firebase_uid: "uid_limiter", email: "limiter@example.com") }
  let(:other_user) { User.create!(firebase_uid: "uid_limiter_other", email: "limiter-other@example.com") }

  def rows_sent(owner, date = Time.zone.today)
    AiUsageCounter.find_by(user_key: owner&.id || AiUsageCounter::GLOBAL_KEY, usage_date: date)&.rows_sent
  end

  describe "既定値と環境変数" do
    it "未設定なら 300 / 500 / 2,000" do
      expect(described_class.max_rows_per_import).to eq(300)
      expect(described_class.max_rows_per_user_per_day).to eq(500)
      expect(described_class.max_rows_per_day).to eq(2_000)
    end

    it "環境変数で変えられ、0（AI を使わない）も受け付ける" do
      with_limit_env("AI_MAX_ROWS_PER_IMPORT" => 10, "AI_MAX_ROWS_PER_USER_PER_DAY" => 0, "AI_MAX_ROWS_PER_DAY" => 99)
      expect(described_class.max_rows_per_import).to eq(10)
      expect(described_class.max_rows_per_user_per_day).to eq(0)
      expect(described_class.max_rows_per_day).to eq(99)
    end

    it "数値でない・負の値なら既定値に戻す" do
      with_limit_env("AI_MAX_ROWS_PER_IMPORT" => "abc", "AI_MAX_ROWS_PER_DAY" => "-1")
      expect(described_class.max_rows_per_import).to eq(300)
      expect(described_class.max_rows_per_day).to eq(2_000)
    end
  end

  describe "#reserve" do
    it "上限内なら全部許し、ユーザーと全体の両方に加算する" do
      expect(described_class.new(user: user).reserve(10)).to eq(10)
      expect(rows_sent(user)).to eq(10)
      expect(rows_sent(nil)).to eq(10)
    end

    it "0 件の予約では行を作らない" do
      expect(described_class.new(user: user).reserve(0)).to eq(0)
      expect(AiUsageCounter.count).to eq(0)
    end

    it "取り込み 1 回の上限は、同じ limiter で複数回予約しても合計で効く" do
      with_limit_env("AI_MAX_ROWS_PER_IMPORT" => 5)
      limiter = described_class.new(user: user)
      expect(limiter.reserve(3)).to eq(3)
      expect(limiter.reserve(3)).to eq(2)
      expect(limiter.reserve(1)).to eq(0)
      expect(rows_sent(user)).to eq(5)
    end

    it "1 ユーザー 1 日の上限は、取り込みをまたいで効く" do
      with_limit_env("AI_MAX_ROWS_PER_USER_PER_DAY" => 5)
      expect(described_class.new(user: user).reserve(4)).to eq(4)
      expect(described_class.new(user: user).reserve(4)).to eq(1)
      expect(described_class.new(user: other_user).reserve(4)).to eq(4)
      expect(rows_sent(user)).to eq(5)
    end

    it "全体 1 日の上限は、ユーザーをまたいで効く" do
      with_limit_env("AI_MAX_ROWS_PER_DAY" => 5)
      expect(described_class.new(user: user).reserve(4)).to eq(4)
      expect(described_class.new(user: other_user).reserve(4)).to eq(1)
      expect(rows_sent(nil)).to eq(5)
      expect(rows_sent(other_user)).to eq(1)
    end

    it "上限を下げて既に超えていても、負の値にはならない" do
      described_class.new(user: user).reserve(10)
      with_limit_env("AI_MAX_ROWS_PER_USER_PER_DAY" => 3)
      expect(described_class.new(user: user).reserve(5)).to eq(0)
      expect(rows_sent(user)).to eq(10)
    end

    it "日付（Asia/Tokyo の 0 時）が変わるとリセットされる" do
      with_limit_env("AI_MAX_ROWS_PER_USER_PER_DAY" => 5)
      travel_to Time.zone.local(2026, 10, 12, 23, 59) do
        expect(described_class.new(user: user).reserve(5)).to eq(5)
        expect(described_class.new(user: user).reserve(1)).to eq(0)
      end
      travel_to Time.zone.local(2026, 10, 13, 0, 0) do
        expect(described_class.new(user: user).reserve(5)).to eq(5)
      end
      expect(rows_sent(user, Date.new(2026, 10, 12))).to eq(5)
      expect(rows_sent(user, Date.new(2026, 10, 13))).to eq(5)
    end

    it "全体の行はユーザーごとの行と別に 1 日 1 行だけ作る" do
      described_class.new(user: user).reserve(1)
      described_class.new(user: other_user).reserve(1)
      expect(AiUsageCounter.global.where(usage_date: Time.zone.today).count).to eq(1)
      expect(AiUsageCounter.global.first.user_id).to be_nil
    end
  end
end
