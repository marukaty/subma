require "rails_helper"

RSpec.describe "CsvImports::Retries", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_retry", email: "retry@example.com") }
  let(:other_user) { User.create!(firebase_uid: "uid_retry_other", email: "retry-other@example.com") }

  def create_import(owner, status:, file: true)
    ci = owner.csv_imports.create!(filename: "x.csv", format: :rakuten, status: status)
    ci.file.attach(io: StringIO.new("dummy"), filename: "x.csv", content_type: "text/csv") if file
    ci
  end

  describe "POST /csv_imports/:csv_import_id/retry" do
    context "未ログイン" do
      it "ログイン画面へリダイレクトし、状態を変えない" do
        ci = create_import(user, status: :failed)
        post csv_import_retry_path(ci)
        expect(response).to redirect_to(login_path)
        expect(ci.reload.status).to eq("failed")
      end
    end

    context "ログイン済み" do
      before { sign_in_as(user) }

      it "failed の import を uploading に戻して再登録する" do
        ci = create_import(user, status: :failed)

        expect {
          post csv_import_retry_path(ci)
        }.to have_enqueued_job(ProcessCsvJob).with(ci.id)

        expect(response).to redirect_to(csv_import_path(ci))
        expect(flash[:notice]).to eq("再実行を開始しました")
        expect(ci.reload.status).to eq("uploading")
      end

      it "監査ログを残す" do
        ci = create_import(user, status: :failed)
        expect { post csv_import_retry_path(ci) }.to change(AuditLog, :count).by(1)
        log = AuditLog.last
        expect(log.action).to eq("retries.create")
        expect(log.resource_id).to eq(ci.id)
      end

      it "同じユーザーの別の import が処理中なら、戻すだけで登録は見送る" do
        create_import(user, status: :processing)
        ci = create_import(user, status: :failed)

        expect {
          post csv_import_retry_path(ci)
        }.not_to have_enqueued_job(ProcessCsvJob)

        expect(flash[:notice]).to include("処理中の取り込みが終わると自動で開始します")
        expect(ci.reload.status).to eq("uploading")
      end

      %i[uploading processing completed].each do |status|
        it "#{status} の import は再実行できない" do
          ci = create_import(user, status: status)

          expect {
            post csv_import_retry_path(ci)
          }.not_to have_enqueued_job(ProcessCsvJob)

          expect(response).to redirect_to(csv_import_path(ci))
          expect(flash[:alert]).to eq("この取り込みは再実行できません")
          expect(ci.reload.status).to eq(status.to_s)
        end
      end

      it "ファイルが残っていなければ再アップロードを案内する" do
        ci = create_import(user, status: :failed, file: false)
        post csv_import_retry_path(ci)
        expect(flash[:alert]).to include("もう一度アップロードしてください")
        expect(ci.reload.status).to eq("failed")
      end

      it "他人の import は 404 で、状態を変えない" do
        ci = create_import(other_user, status: :failed)
        post csv_import_retry_path(ci)
        expect(response).to have_http_status(:not_found)
        expect(ci.reload.status).to eq("failed")
      end

      it "GET では受け付けない" do
        ci = create_import(user, status: :failed)
        get "/csv_imports/#{ci.id}/retry"
        expect(response).to have_http_status(:not_found)
        expect(ci.reload.status).to eq("failed")
      end
    end
  end

  describe "GET /csv_imports/:id（再実行ボタンの表示）" do
    before { sign_in_as(user) }

    it "failed でファイルが残っていれば「再実行」ボタン（POST フォーム）を出す" do
      ci = create_import(user, status: :failed)
      get csv_import_path(ci)
      expect(response.body).to include(csv_import_retry_path(ci))
      expect(response.body).to include("再実行")
    end

    it "ファイルが残っていなければボタンを出さない" do
      ci = create_import(user, status: :failed, file: false)
      get csv_import_path(ci)
      expect(response.body).not_to include(csv_import_retry_path(ci))
    end

    it "処理中のまま止まったものは自動リロードを止めてボタンを出す" do
      ci = create_import(user, status: :ai_analyzing)
      ci.update_columns(updated_at: 31.minutes.ago)
      get csv_import_path(ci)
      expect(response.body).not_to include('http-equiv="refresh"')
      expect(response.body).to include(csv_import_retry_path(ci))
    end

    it "同じユーザーの処理中があれば待ちのメッセージを出す" do
      create_import(user, status: :processing)
      ci = create_import(user, status: :uploading)
      get csv_import_path(ci)
      expect(response.body).to include("別の取り込みを処理中です")
    end
  end
end
