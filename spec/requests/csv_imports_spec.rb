require "rails_helper"

RSpec.describe "CsvImports", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_csv_req", email: "csvreq@example.com") }
  let(:csv_path) { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }

  context "未ログイン時" do
    it "GET /csv_imports は /login にリダイレクト" do
      get csv_imports_path
      expect(response).to redirect_to(login_path)
    end
  end

  context "ログイン済み" do
    before { sign_in_as(user) }

    describe "GET /csv_imports" do
      it "200 OK" do
        get csv_imports_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "GET /csv_imports/new" do
      it "200 OK" do
        get new_csv_import_path
        expect(response).to have_http_status(:ok)
      end
    end

    describe "POST /csv_imports" do
      let(:upload) do
        Rack::Test::UploadedFile.new(csv_path, "text/csv")
      end

      it "CsvImport を作成して ProcessCsvJob を enqueue する" do
        expect {
          post csv_imports_path, params: { csv_import: { format: "rakuten", file: upload } }
        }.to change(CsvImport, :count).by(1)

        ci = CsvImport.last
        expect(ProcessCsvJob).to have_been_enqueued.with(ci.id)
        expect(response).to redirect_to(csv_import_path(ci))
      end

      it "ファイルなしは弾かれる" do
        post csv_imports_path, params: { csv_import: { format: "rakuten" } }
        expect(response).to redirect_to(new_csv_import_path)
      end
    end

    describe "GET /csv_imports/:id" do
      it "200 OK & 自分のレコードを表示" do
        ci = current_user_csv_import
        get csv_import_path(ci)
        expect(response).to have_http_status(:ok)
        expect(response.body).to include(ci.filename)
      end

      it "他ユーザーのレコードは 404" do
        other = User.create!(firebase_uid: "uid_other_csv", email: "o@example.com")
        ci = other.csv_imports.create!(filename: "x.csv", format: :rakuten, status: :uploading)
        get csv_import_path(ci)
        expect(response).to have_http_status(:not_found)
      end
    end

    describe "POST /csv_imports/:id/register" do
      let(:csv_import) { user.csv_imports.create!(filename: "x.csv", format: :rakuten, status: :completed) }
      let!(:tx_sub) do
        csv_import.transactions.create!(
          user: user, transaction_date: Date.new(2026, 4, 1),
          amount: 1490, description: "NETFLIX.COM",
          classification: :subscription, classifier: :rule, confidence: 1.0,
          inferred_service_name: "Netflix", inferred_category: "エンタメ"
        )
      end

      it "チェックされた行をサブスクとして一括登録する" do
        expect {
          post register_csv_import_path(csv_import), params: {
            selections: {
              tx_sub.id.to_s => { include: "1", service_name: "Netflix", category: "エンタメ", amount: "1490" }
            }
          }
        }.to change(Subscription, :count).by(1)

        sub = Subscription.last
        expect(sub.service_name).to eq("Netflix")
        expect(sub.category).to eq("エンタメ")
        expect(sub.amount).to eq(1490)
        expect(sub.source).to eq("csv")
        expect(sub.user).to eq(user)
        expect(tx_sub.reload.matched_subscription).to eq(sub)
        expect(response).to redirect_to(subscriptions_path)
      end

      it "チェック無しの行は登録されない" do
        expect {
          post register_csv_import_path(csv_import), params: {
            selections: {
              tx_sub.id.to_s => { include: "0", service_name: "Netflix", category: "エンタメ", amount: "1490" }
            }
          }
        }.not_to change(Subscription, :count)
      end

      it "AI 判定の取引は source: ai で登録される" do
        ai_tx = csv_import.transactions.create!(
          user: user, transaction_date: Date.new(2026, 4, 3),
          amount: 2000, description: "MYSTERY SUBSCRIPTION",
          classification: :subscription, classifier: :ai, confidence: 0.9,
          inferred_service_name: "Mystery", inferred_category: "その他"
        )
        post register_csv_import_path(csv_import), params: {
          selections: {
            ai_tx.id.to_s => { include: "1", service_name: "Mystery", category: "その他", amount: "2000" }
          }
        }
        expect(Subscription.last.source).to eq("ai")
      end

      it "他ユーザーの csv_import に対しては 404" do
        other = User.create!(firebase_uid: "uid_other_register", email: "o2@example.com")
        other_ci = other.csv_imports.create!(filename: "y.csv", format: :rakuten, status: :completed)
        post register_csv_import_path(other_ci), params: { selections: {} }
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  def current_user_csv_import
    user.csv_imports.create!(filename: "test.csv", format: :rakuten, status: :uploading)
  end
end
