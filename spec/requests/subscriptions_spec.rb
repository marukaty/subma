require "rails_helper"

RSpec.describe "Subscriptions", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_sub_req", email: "sub_req@example.com") }
  let(:other_user) { User.create!(firebase_uid: "uid_other", email: "other@example.com") }

  let(:valid_params) do
    {
      service_name: "Netflix Premium",
      amount: 1980,
      currency: "JPY",
      billing_cycle: "monthly",
      next_billing_date: 7.days.from_now.to_date,
      payment_method: "楽天カード",
      category: "エンタメ",
      status: "active",
      memo: "家族で利用"
    }
  end

  context "未ログイン時" do
    it "GET /subscriptions は /login にリダイレクト" do
      get subscriptions_path
      expect(response).to redirect_to(login_path)
    end
  end

  context "ログイン済み" do
    before { sign_in_as(user) }

    describe "GET /subscriptions" do
      it "200 OK を返す" do
        get subscriptions_path
        expect(response).to have_http_status(:ok)
      end

      it "他ユーザーのサブスクは表示されない" do
        own = user.subscriptions.create!(valid_params.merge(service_name: "OwnSub"))
        others = other_user.subscriptions.create!(valid_params.merge(service_name: "OtherSub"))
        get subscriptions_path
        expect(response.body).to include("OwnSub")
        expect(response.body).not_to include("OtherSub")
      end
    end

    describe "POST /subscriptions" do
      it "サブスクを作成する" do
        expect {
          post subscriptions_path, params: { subscription: valid_params }
        }.to change(user.subscriptions, :count).by(1)
        expect(response).to redirect_to(subscriptions_path)
      end

      it "source は manual で固定される" do
        post subscriptions_path, params: { subscription: valid_params.merge(source: "ai") }
        expect(user.subscriptions.last.source).to eq("manual")
      end

      it "AuditLog が記録される" do
        expect {
          post subscriptions_path, params: { subscription: valid_params }
        }.to change(AuditLog, :count).by(1)
        expect(AuditLog.last.action).to eq("subscriptions.create")
        expect(AuditLog.last.user_id).to eq(user.id)
      end

      it "バリデーションエラー時は new テンプレートを再描画" do
        post subscriptions_path, params: { subscription: valid_params.merge(service_name: "") }
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    describe "PATCH /subscriptions/:id" do
      let(:subscription) { user.subscriptions.create!(valid_params) }

      it "更新する" do
        patch subscription_path(subscription), params: { subscription: { amount: 2980 } }
        expect(subscription.reload.amount).to eq(2980)
        expect(response).to redirect_to(subscriptions_path)
      end

      it "他ユーザーのサブスクは更新できない（404）" do
        other_sub = other_user.subscriptions.create!(valid_params)
        patch subscription_path(other_sub), params: { subscription: { amount: 9999 } }
        expect(response).to have_http_status(:not_found)
        expect(other_sub.reload.amount).to eq(valid_params[:amount])
      end
    end

    describe "DELETE /subscriptions/:id" do
      let!(:subscription) { user.subscriptions.create!(valid_params) }

      it "削除する" do
        expect {
          delete subscription_path(subscription)
        }.to change(user.subscriptions, :count).by(-1)
      end
    end

    describe "PATCH /subscriptions/:id/pause /resume /cancel" do
      let(:subscription) { user.subscriptions.create!(valid_params.merge(status: "active")) }

      it "pause で paused に遷移" do
        patch pause_subscription_path(subscription)
        expect(subscription.reload.status).to eq("paused")
      end

      it "resume で paused -> active" do
        subscription.update!(status: :paused)
        patch resume_subscription_path(subscription)
        expect(subscription.reload.status).to eq("active")
      end

      it "cancel で cancelled" do
        patch cancel_subscription_path(subscription)
        expect(subscription.reload.status).to eq("cancelled")
      end

      it "cancel で cancelled_at が今日にセットされる" do
        expect(subscription.cancelled_at).to be_nil
        patch cancel_subscription_path(subscription)
        expect(subscription.reload.cancelled_at).to eq(Date.current)
      end

      it "cancel で既に cancelled_at がある場合は上書きしない" do
        subscription.update!(cancelled_at: 30.days.ago.to_date)
        patch cancel_subscription_path(subscription)
        expect(subscription.reload.cancelled_at).to eq(30.days.ago.to_date)
      end

      it "resume で cancelled_at がクリアされる" do
        subscription.update!(status: :cancelled, cancelled_at: 5.days.ago.to_date)
        patch resume_subscription_path(subscription)
        expect(subscription.reload.cancelled_at).to be_nil
        expect(subscription.reload.status).to eq("active")
      end
    end
  end
end
