require "rails_helper"

# 試用者向けの案内（評価用であること・サンプル CSV・全削除の導線）
RSpec.describe "試用者向けの案内", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_trial", email: "trial@example.com") }

  before { sign_in_as(user) }

  [ [ "ダッシュボード", :dashboard_path ], [ "CSV 取り込み画面", :new_csv_import_path ] ].each do |label, path|
    it "#{label}に、評価用である旨・サンプル CSV・全削除の案内を表示する" do
      get public_send(path)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("このサービスは評価用です")
      expect(response.body).to include(%(href="/samples/sample_rakuten.csv"))
      expect(response.body).to include("#{settings_path}#account-deletion")
    end
  end

  it "サンプル CSV をダウンロードできる" do
    get "/samples/sample_rakuten.csv"
    expect(response).to have_http_status(:ok)
    expect(response.body.b).to start_with("\xEF\xBB\xBF".b)
  end
end
