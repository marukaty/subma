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

      context "ジョブを実際に動かす（ADR-0007: 二重実行の防止）" do
        before { allow_any_instance_of(ProcessCsvJob).to receive(:perform).and_call_original }

        %i[processing completed failed].each do |status|
          it "#{status} の import への再送は何もせず 200（Cloud Tasks に再送させない）" do
            csv_import.update!(status: status)
            expect(Csv::Parser).not_to receive(:new)

            post url, params: { csv_import_id: csv_import.id }

            expect(response).to have_http_status(:ok)
            expect(JSON.parse(response.body)["result"]).to eq("skipped")
            expect(csv_import.reload.status).to eq(status.to_s)
          end
        end

        it "処理が失敗しても 200 を返し、import は failed になる" do
          csv_import.file.attach(io: StringIO.new("broken"), filename: "x.csv", content_type: "text/csv")
          allow(Csv::Parser).to receive(:new).and_raise(ArgumentError, "boom")

          post url, params: { csv_import_id: csv_import.id }

          expect(response).to have_http_status(:ok)
          expect(JSON.parse(response.body)["result"]).to eq("failed")
          expect(csv_import.reload.status).to eq("failed")
        end
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
      let(:tasks_sa_email) { "tasks@subma-test.iam.gserviceaccount.com" }

      before do
        ENV["ENABLE_OIDC_VERIFICATION"] = "true"
        ENV["CLOUD_TASKS_TARGET_URL"] = audience
        ENV["CLOUD_TASKS_SA_EMAIL"] = tasks_sa_email
      end

      after do
        ENV.delete("ENABLE_OIDC_VERIFICATION")
        ENV.delete("CLOUD_TASKS_TARGET_URL")
        ENV.delete("CLOUD_TASKS_SA_EMAIL")
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
        allow(OidcVerifier).to receive(:new).with(audience: audience, expected_email: tasks_sa_email).and_return(verifier)
        allow(verifier).to receive(:verify).and_raise(OidcVerifier::InvalidTokenError, "expired")

        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Bearer fake" }
        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("invalid token")
      end

      it "OidcVerifier が成功すれば 200 でジョブ実行" do
        verifier = instance_double(OidcVerifier)
        allow(OidcVerifier).to receive(:new).with(audience: audience, expected_email: tasks_sa_email).and_return(verifier)
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

      it "CLOUD_TASKS_SA_EMAIL が未設定だとジョブを実行せず 500（fail-closed）" do
        ENV.delete("CLOUD_TASKS_SA_EMAIL")
        expect_any_instance_of(ProcessCsvJob).not_to receive(:perform)

        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Bearer fake" }
        expect(response).to have_http_status(:internal_server_error)
      end

      it "CLOUD_TASKS_SA_EMAIL が空文字でもジョブを実行せず 500（fail-closed）" do
        ENV["CLOUD_TASKS_SA_EMAIL"] = ""
        expect_any_instance_of(ProcessCsvJob).not_to receive(:perform)

        post url, params: { csv_import_id: csv_import.id }, headers: { "Authorization" => "Bearer fake" }
        expect(response).to have_http_status(:internal_server_error)
      end

      context "実トークンで発行元 SA を確認する（OidcVerifier をモックしない）" do
        let(:rsa_private) { OpenSSL::PKey::RSA.new(2048) }
        let(:kid) { "test-oidc-kid" }
        let(:payload) do
          now = Time.now.to_i
          {
            "iss" => "https://accounts.google.com",
            "aud" => audience,
            "iat" => now - 60,
            "exp" => now + 600,
            "sub" => "12345",
            "email" => tasks_sa_email,
            "email_verified" => true
          }
        end

        before do
          cert = OpenSSL::X509::Certificate.new
          cert.version = 2
          cert.serial = 1
          cert.subject = OpenSSL::X509::Name.parse("/CN=test-oidc")
          cert.issuer = cert.subject
          cert.public_key = rsa_private.public_key
          cert.not_before = Time.now - 60
          cert.not_after = Time.now + 3600
          cert.sign(rsa_private, OpenSSL::Digest.new("SHA256"))
          allow_any_instance_of(OidcVerifier).to receive(:fetch_certs).and_return(kid => cert.to_pem)
        end

        def bearer(claims)
          { "Authorization" => "Bearer #{JWT.encode(claims, rsa_private, 'RS256', { 'kid' => kid })}" }
        end

        it "期待する SA が発行したトークンなら 200" do
          expect_any_instance_of(ProcessCsvJob).to receive(:perform).with(csv_import.id)
          post url, params: { csv_import_id: csv_import.id }, headers: bearer(payload)
          expect(response).to have_http_status(:ok)
        end

        it "別の SA が発行したトークン（aud は正しい）は 401 でジョブを実行しない" do
          expect_any_instance_of(ProcessCsvJob).not_to receive(:perform)
          claims = payload.merge("email" => "attacker@other-project.iam.gserviceaccount.com")
          post url, params: { csv_import_id: csv_import.id }, headers: bearer(claims)
          expect(response).to have_http_status(:unauthorized)
        end

        it "email_verified が false なら 401 でジョブを実行しない" do
          expect_any_instance_of(ProcessCsvJob).not_to receive(:perform)
          post url, params: { csv_import_id: csv_import.id }, headers: bearer(payload.merge("email_verified" => false))
          expect(response).to have_http_status(:unauthorized)
        end
      end
    end
  end
end
