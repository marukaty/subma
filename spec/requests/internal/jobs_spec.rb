require "rails_helper"

RSpec.describe "Internal::Jobs", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_internal_jobs", email: "internal@example.com") }
  let(:csv_import) do
    user.csv_imports.create!(filename: "x.csv", format: :rakuten, status: :uploading)
  end

  before do
    # process_csv は ProcessCsvJob#perform を同期呼び出しするので、
    # ジョブ本体の中身（CSV パース・AI 抽出等）はモックして責務だけを検証する
    allow_any_instance_of(ProcessCsvJob).to receive(:perform).and_return(true)
  end

  describe "POST /internal/jobs/process_csv" do
    let(:url) { "/internal/jobs/process_csv" }

    context "OIDC 検証無効（既定: dev/test 環境かつ ENABLE_OIDC_VERIFICATION 未設定）" do
      it "Authorization ヘッダ無しでも 200 を返す" do
        post url, params: { csv_import_id: csv_import.id }
        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["ok"]).to eq(true)
        expect(body["csv_import_id"]).to eq(csv_import.id)
      end

      it "ProcessCsvJob#perform を同期実行する" do
        expect_any_instance_of(ProcessCsvJob).to receive(:perform).with(csv_import.id)
        post url, params: { csv_import_id: csv_import.id }
      end

      it "csv_import_id が無いと 400" do
        post url, params: {}
        expect(response).to have_http_status(:bad_request)
      end
    end

    context "OIDC 検証有効（ENABLE_OIDC_VERIFICATION=true）" do
      let(:audience) { "https://subma.example.com/internal/jobs/process_csv" }

      before do
        ENV["ENABLE_OIDC_VERIFICATION"] = "true"
        ENV["CLOUD_TASKS_TARGET_URL"] = audience
      end

      after do
        ENV.delete("ENABLE_OIDC_VERIFICATION")
        ENV.delete("CLOUD_TASKS_TARGET_URL")
      end

      it "Authorization ヘッダ無しは 401" do
        post url, params: { csv_import_id: csv_import.id }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("missing bearer token")
      end

      it "Bearer 形式でないトークンは 401" do
        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Basic xyz" }
        expect(response).to have_http_status(:unauthorized)
      end

      it "OidcVerifier が InvalidTokenError を投げると 401" do
        verifier = instance_double(OidcVerifier)
        allow(OidcVerifier).to receive(:new).with(audience: audience).and_return(verifier)
        allow(verifier).to receive(:verify).and_raise(OidcVerifier::InvalidTokenError, "expired")

        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Bearer fake" }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("invalid token")
      end

      it "OidcVerifier が成功すれば 200 でジョブ実行" do
        verifier = instance_double(OidcVerifier)
        allow(OidcVerifier).to receive(:new).with(audience: audience).and_return(verifier)
        allow(verifier).to receive(:verify).and_return("sub" => "tasks-sa")

        expect_any_instance_of(ProcessCsvJob).to receive(:perform).with(csv_import.id)

        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Bearer fake" }
        expect(response).to have_http_status(:ok)
      end

      it "CLOUD_TASKS_TARGET_URL が未設定だと 500（サーバー設定不備）" do
        ENV.delete("CLOUD_TASKS_TARGET_URL")
        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Bearer fake" }
        expect(response).to have_http_status(:internal_server_error)
      end
    end
  end
end
