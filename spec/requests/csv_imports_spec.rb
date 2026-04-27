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
  end

  def current_user_csv_import
    user.csv_imports.create!(filename: "test.csv", format: :rakuten, status: :uploading)
  end
end
