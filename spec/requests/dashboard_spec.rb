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

    it "解約済みサブスクは集計対象外" do
      user.subscriptions.create!(base_attrs.merge(service_name: "Cancelled", amount: 99_999, status: "cancelled"))
      get dashboard_path
      expect(response.body).not_to include("¥99,999")
    end
  end
end
