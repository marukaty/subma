require "rails_helper"

RSpec.describe "Settings", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_set", email: "set@example.com", notification_enabled: true) }

  context "未ログイン時" do
    it "GET /settings は /login にリダイレクト" do
      get settings_path
      expect(response).to redirect_to(login_path)
    end
  end

  context "ログイン済み" do
    before { sign_in_as(user) }

    describe "GET /settings" do
      it "200 OK" do
        get settings_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(user.email)
      end

      it "登録中のカテゴリと件数が表示される" do
        user.subscriptions.create!(
          service_name: "X", amount: 100, currency: "JPY",
          billing_cycle: "monthly", status: "active", source: "manual",
          category: "テストCat"
        )
        get settings_path
        expect(response.body).to include("テストCat")
      end
    end

    describe "PATCH /settings" do
      it "通知設定を更新する" do
        patch settings_path, params: { user: { notification_enabled: "0" } }
        expect(user.reload.notification_enabled).to be(false)
        expect(response).to redirect_to(settings_path)
      end

      it "AuditLog を記録する" do
        expect {
          patch settings_path, params: { user: { notification_enabled: "0" } }
        }.to change(AuditLog, :count).by(1)
        expect(AuditLog.last.action).to eq("settings.update")
      end
    end
  end
end
