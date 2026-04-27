require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_dash", email: "dash@example.com") }

  context "未ログイン時" do
    it "GET /dashboard は /login にリダイレクト" do
      get dashboard_path
      expect(response).to redirect_to(login_path)
    end
  end

  context "ログイン済み" do
    before { sign_in_as(user) }

    let(:base_attrs) do
      {
        currency: "JPY", billing_cycle: "monthly", status: "active",
        source: "manual", started_at: 6.months.ago.to_date
      }
    end

    it "サブスクなしで 200" do
      get dashboard_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("まだサブスクが登録されていません")
    end

    it "月額・年額・件数が表示される" do
      user.subscriptions.create!(base_attrs.merge(service_name: "Netflix", amount: 1490, category: "エンタメ"))
      user.subscriptions.create!(base_attrs.merge(service_name: "GitHub", amount: 600, category: "仕事"))
      get dashboard_path
      expect(response.body).to include("¥2,090")  # 月額合計
      expect(response.body).to include("2") # 件数
    end

    it "他ユーザーのサブスクは集計に含まれない" do
      other = User.create!(firebase_uid: "uid_other_dash", email: "od@example.com")
      other.subscriptions.create!(base_attrs.merge(service_name: "Other", amount: 99_999, category: "他"))
      user.subscriptions.create!(base_attrs.merge(service_name: "Mine", amount: 1000, category: "エンタメ"))
      get dashboard_path
      expect(response.body).to include("¥1,000")
      expect(response.body).not_to include("¥99,999")
    end

    it "今後 30 日の引落予定が表示される" do
      user.subscriptions.create!(base_attrs.merge(
        service_name: "Soon",
        amount: 1500,
        next_billing_date: 5.days.from_now.to_date
      ))
      get dashboard_path
      expect(response.body).to include("Soon")
    end

    it "解約済みサブスクは月額/年額の集計対象外" do
      user.subscriptions.create!(base_attrs.merge(service_name: "Cancelled", amount: 99_999, status: "cancelled"))
      get dashboard_path
      expect(response.body).not_to include("¥99,999")
    end

    describe "月間推移グラフのデータ" do
      it "started_at の異なるサブスクがあれば月により値が変わる" do
        # 8 ヶ月前に始まった旧サブスク（4,000）と先月始まった新サブスク（1,000）
        user.subscriptions.create!(base_attrs.merge(
          service_name: "Old",
          amount: 4000,
          started_at: 8.months.ago.to_date
        ))
        user.subscriptions.create!(base_attrs.merge(
          service_name: "New",
          amount: 1000,
          started_at: 1.month.ago.to_date
        ))
        get dashboard_path

        # chartkick の JSON データには 4000 と 5000 の両方が現れるはず
        expect(response.body).to match(/4000(\.0)?/)
        expect(response.body).to match(/5000(\.0)?/)
      end

      it "解約済みサブスクは cancelled_at 以降の月に含まれない（過去の月にはカウント）" do
        user.subscriptions.create!(base_attrs.merge(
          service_name: "Now",
          amount: 1000,
          status: "active",
          started_at: 10.months.ago.to_date
        ))
        user.subscriptions.create!(base_attrs.merge(
          service_name: "Old",
          amount: 50_000,
          status: "cancelled",
          started_at: 12.months.ago.to_date,
          cancelled_at: 4.months.ago.to_date
        ))
        get dashboard_path
        # 過去の active 期間は Now(1k) + Old(50k) = 51,000
        expect(response.body).to match(/51000(\.0)?/)
        # 解約後は Now のみで 1,000
        expect(response.body).to match(/1000(\.0)?/)
      end
    end
  end
end
