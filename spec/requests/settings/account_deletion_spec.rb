require "rails_helper"

RSpec.describe "退会（DELETE /settings/account）", type: :request do
  let(:user) { User.create!(firebase_uid: "uid_del", email: "Delete.Me@example.com", display_name: "del") }
  let(:other) { User.create!(firebase_uid: "uid_keep", email: "keep@example.com", display_name: "keep") }
  let(:csv_path) { Rails.root.join("spec/fixtures/csv/rakuten_sample_utf8.csv") }

  def create_data_for(owner, label)
    sub = owner.subscriptions.create!(
      service_name: "#{label} sub", amount: 980, currency: "JPY",
      billing_cycle: "monthly", status: "active", source: "csv"
    )
    import = owner.csv_imports.create!(filename: "#{label}.csv", format: "rakuten", status: "failed")
    import.file.attach(io: File.open(csv_path), filename: "#{label}.csv", content_type: "text/csv")
    owner.transactions.create!(
      csv_import: import, transaction_date: Date.new(2026, 8, 1), amount: 980,
      description: "#{label} SHOP", matched_subscription: sub
    )
    AuditLog.create!(user: owner, action: "subscriptions.create")
    { subscription: sub, csv_import: import, blob: import.file.blob }
  end

  context "未ログイン時" do
    it "ログイン画面にリダイレクトし、何も削除しない" do
      create_data_for(other, "other")
      expect {
        delete settings_account_path, params: { confirmation_email: other.email }
      }.not_to change(User, :count)
      expect(response).to redirect_to(login_path)
    end

    it "JSON では 401" do
      delete settings_account_path, params: { confirmation_email: "x@example.com" }, as: :json
      expect(response).to have_http_status(:unauthorized)
    end
  end

  context "ログイン済み" do
    let!(:own) { create_data_for(user, "own") }
    let!(:others) { create_data_for(other, "other") }

    before { sign_in_as(user) }

    describe "確認のメールアドレスが一致する" do
      subject(:delete_account) do
        delete settings_account_path, params: { confirmation_email: " delete.me@EXAMPLE.com " }
      end

      it "本人のユーザー・サブスク・取り込み・明細を削除する" do
        user_id = user.id
        delete_account

        expect(User.exists?(user_id)).to be(false)
        expect(Subscription.where(user_id: user_id)).to be_empty
        expect(CsvImport.where(user_id: user_id)).to be_empty
        expect(Transaction.where(user_id: user_id)).to be_empty
      end

      it "添付ファイル（blob と紐付け）を purge する" do
        blob = own[:blob]
        expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(true)

        delete_account

        expect(ActiveStorage::Blob.exists?(blob.id)).to be(false)
        expect(ActiveStorage::Attachment.where(blob_id: blob.id)).to be_empty
        expect(ActiveStorage::Blob.service.exist?(blob.key)).to be(false)
      end

      it "本人の監査ログは消し、削除の依頼と完了だけを user_id なしで残す（メールは記録しない）" do
        user_id = user.id
        delete_account

        expect(AuditLog.where(user_id: user_id)).to be_empty
        requested = AuditLog.where(action: AuditLog::ACTION_ACCOUNT_DELETE_REQUESTED)
        deleted = AuditLog.where(action: AuditLog::ACTION_ACCOUNT_DELETED)
        expect(requested.count).to eq(1)
        expect(deleted.count).to eq(1)
        expect(requested.first.user_id).to be_nil
        expect(deleted.first.user_id).to be_nil
        expect(AuditLog.pluck(:action, :resource_type, :user_agent).flatten.compact.join)
          .not_to match(/delete\.me@example\.com/i)
      end

      it "他のユーザーのデータは残す" do
        delete_account

        expect(User.exists?(other.id)).to be(true)
        expect(other.subscriptions.count).to eq(1)
        expect(other.csv_imports.count).to eq(1)
        expect(other.transactions.count).to eq(1)
        expect(others[:csv_import].reload.file).to be_attached
        expect(AuditLog.where(user_id: other.id, action: "subscriptions.create").count).to eq(1)
      end

      it "セッションを破棄してログイン画面へ。以降は未ログイン扱い" do
        delete_account

        expect(response).to redirect_to(login_path)
        expect(flash[:notice]).to include("削除しました")
        get settings_path
        expect(response).to redirect_to(login_path)
      end

      it "ログイン画面でブラウザ側の Firebase のログイン状態を消す目印を出す" do
        delete_account
        follow_redirect!
        expect(response.body).to include("firebase-sign-out-on-load")
        expect(response.body).to include("削除しました")
      end

      it "共通の監査ログ（settings.destroy_account）は記録しない" do
        delete_account
        expect(AuditLog.where(action: "settings.destroy_account")).to be_empty
      end
    end

    describe "確認のメールアドレスが一致しない" do
      it "422 を返し、何も削除しない" do
        expect {
          delete settings_account_path, params: { confirmation_email: "wrong@example.com" }
        }.not_to change { [ User.count, Subscription.count, CsvImport.count, Transaction.count ] }

        expect(response).to have_http_status(:unprocessable_content)
        expect(response.body).to include("一致しません")
        expect(own[:csv_import].reload.file).to be_attached
      end

      it "空なら 422" do
        delete settings_account_path, params: { confirmation_email: "" }
        expect(response).to have_http_status(:unprocessable_content)
        expect(User.exists?(user.id)).to be(true)
      end

      it "削除の依頼だけを user_id 付きで記録する" do
        delete settings_account_path, params: { confirmation_email: "wrong@example.com" }
        log = AuditLog.find_by(action: AuditLog::ACTION_ACCOUNT_DELETE_REQUESTED)
        expect(log.user_id).to eq(user.id)
        expect(AuditLog.where(action: AuditLog::ACTION_ACCOUNT_DELETED)).to be_empty
      end
    end

    describe "CSRF 対策" do
      # ログイン（before）が済んでから、この例の中だけ CSRF の検証を有効にする
      def with_forgery_protection
        original = ActionController::Base.allow_forgery_protection
        ActionController::Base.allow_forgery_protection = true
        yield
      ensure
        ActionController::Base.allow_forgery_protection = original
      end

      it "トークンなしでは削除しない" do
        with_forgery_protection do
          delete settings_account_path, params: { confirmation_email: user.email }
        end
        expect(response).to have_http_status(:unprocessable_content)
        expect(User.exists?(user.id)).to be(true)
      end

      it "設定画面のフォームのトークンなら削除できる" do
        with_forgery_protection do
          get settings_path
          form = response.body[%r{<form[^>]*action="#{settings_account_path}".*?</form>}m]
          token = form[/name="authenticity_token" value="([^"]+)"/, 1]
          expect(token).to be_present

          delete settings_account_path, params: { confirmation_email: user.email, authenticity_token: token }
        end
        expect(response).to redirect_to(login_path)
        expect(User.exists?(user.id)).to be(false)
      end
    end
  end

  describe "設定画面" do
    before { sign_in_as(user) }

    it "削除ボタンと、Google アカウントは削除しない旨を表示する" do
      get settings_path
      expect(response.body).to include("アカウントとすべてのデータを削除")
      expect(response.body).to include("Google アカウントは削除しません")
      expect(response.body).to include(%(name="confirmation_email"))
    end
  end
end
