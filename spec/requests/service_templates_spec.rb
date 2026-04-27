require "rails_helper"

RSpec.describe "ServiceTemplates", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_tpl", email: "tpl@example.com") }

  context "未ログイン時" do
    it "GET /service_templates.json は 401 (JSON では unauthorized)" do
      get service_templates_path(format: :json)
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "ログイン済み" do
    before { sign_in_as(user) }

    it "JSON 配列で返す" do
      ServiceTemplate.create!(service_name: "TestTplA", default_billing_cycle: :monthly)
      get service_templates_path(format: :json)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body).to be_an(Array)
      expect(body.first).to include("service_name", "default_amount", "default_billing_cycle")
    end
  end
end
