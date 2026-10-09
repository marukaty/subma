require "rails_helper"

RSpec.describe "Auth", type: :request do
  describe "GET /login" do
    it "renders login page" do
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Google")
    end

    it "redirects to dashboard if already signed in" do
      user = User.create!(firebase_uid: "uid_signed_in", email: "x@example.com")
      sign_in_as(user)
      get login_path
      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "POST /auth/sign_in" do
    let(:claims) do
      {
        "sub" => "uid_new",
        "email" => "new@example.com",
        "email_verified" => true,
        "name" => "New User",
        "firebase" => { "sign_in_provider" => "google.com" }
      }
    end

    context "with a valid id token" do
      before do
        verifier = instance_double(FirebaseAuthVerifier, verify: claims)
        allow(FirebaseAuthVerifier).to receive(:new).and_return(verifier)
      end

      it "creates a user and starts a session" do
        expect {
          post auth_sign_in_path, params: { id_token: "valid.jwt.token" }, as: :json
        }.to change(User, :count).by(1)

        expect(response).to have_http_status(:ok)
        body = JSON.parse(response.body)
        expect(body["ok"]).to be(true)
        expect(body["redirect_to"]).to eq(dashboard_path)
        expect(session[:user_id]).to eq(User.last.id)
      end

      it "records an audit log for sign_in" do
        expect {
          post auth_sign_in_path, params: { id_token: "valid.jwt.token" }, as: :json
        }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.action).to eq(AuditLog::ACTION_AUTH_SIGN_IN)
        expect(log.user_id).to eq(User.last.id)
      end
    end

    context "with an invalid id token" do
      before do
        verifier = instance_double(FirebaseAuthVerifier)
        allow(verifier).to receive(:verify).and_raise(FirebaseAuthVerifier::InvalidTokenError, "bad token")
        allow(FirebaseAuthVerifier).to receive(:new).and_return(verifier)
      end

      it "returns 401 and does not start a session" do
        expect {
          post auth_sign_in_path, params: { id_token: "bad.token" }, as: :json
        }.not_to change(User, :count)

        expect(response).to have_http_status(:unauthorized)
        expect(JSON.parse(response.body)["error"]).to eq("invalid_token")
        expect(session[:user_id]).to be_nil
      end

      it "records an audit log for sign_in_failed" do
        expect {
          post auth_sign_in_path, params: { id_token: "bad.token" }, as: :json
        }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.action).to eq(AuditLog::ACTION_AUTH_SIGN_IN_FAILED)
        expect(log.user_id).to be_nil
      end
    end
  end

  describe "POST /auth/sign_in with the login allowlist" do
    let(:claims) do
      {
        "sub" => "uid_candidate",
        "email" => "Invited@Example.com",
        "email_verified" => true,
        "name" => "Candidate",
        "firebase" => { "sign_in_provider" => "google.com" }
      }
    end

    before { with_allowed_login_emails(" invited@example.com , other@example.org ") }

    def post_sign_in(token_claims)
      stub_firebase_verifier(token_claims)
      post auth_sign_in_path, params: { id_token: "valid.jwt.token" }, as: :json
    end

    it "allows a listed, verified Google account (case-insensitive)" do
      expect { post_sign_in(claims) }.to change(User, :count).by(1)
      expect(response).to have_http_status(:ok)
      expect(session[:user_id]).to eq(User.last.id)
    end

    shared_examples "a denied sign-in" do |reason|
      it "returns 403 not_allowed without creating a user or a session" do
        expect { post_sign_in(denied_claims) }.not_to change(User, :count)

        expect(response).to have_http_status(:forbidden)
        body = JSON.parse(response.body)
        expect(body["ok"]).to be(false)
        expect(body["error"]).to eq("not_allowed")
        expect(body["message"]).to include("招待制")
        expect(session[:user_id]).to be_nil
      end

      it "records auth.sign_in_denied without the email address" do
        expect { post_sign_in(denied_claims) }.to change(AuditLog, :count).by(1)

        log = AuditLog.last
        expect(log.action).to eq(AuditLog::ACTION_AUTH_SIGN_IN_DENIED)
        expect(log.user_id).to be_nil
        expect(log.attributes.values.compact.map(&:to_s)).not_to include(a_string_including("@"))
      end

      it "logs the reason with a masked email" do
        allow(Rails.logger).to receive(:warn).and_call_original
        post_sign_in(denied_claims)
        expect(Rails.logger).to have_received(:warn).with(a_string_including("reason=#{reason}"))
        if denied_claims["email"].present?
          expect(Rails.logger).not_to have_received(:warn).with(a_string_including(denied_claims["email"].downcase))
        end
      end
    end

    context "when the email is not verified" do
      let(:denied_claims) { claims.merge("email_verified" => false) }

      it_behaves_like "a denied sign-in", "email_not_verified"
    end

    context "when the provider is not Google" do
      let(:denied_claims) { claims.merge("firebase" => { "sign_in_provider" => "password" }) }

      it_behaves_like "a denied sign-in", "provider_not_allowed"
    end

    context "when the email is not on the list" do
      let(:denied_claims) { claims.merge("sub" => "uid_stranger", "email" => "stranger@example.net") }

      it_behaves_like "a denied sign-in", "email_not_listed"
    end

    context "when the token has no email (e.g. anonymous sign-in)" do
      let(:denied_claims) { claims.except("email").merge("firebase" => { "sign_in_provider" => "anonymous" }) }

      it_behaves_like "a denied sign-in", "provider_not_allowed"
    end

    context "when the allowlist is empty (fail-closed)" do
      before { with_allowed_login_emails("") }

      let(:denied_claims) { claims }

      it_behaves_like "a denied sign-in", "email_not_listed"
    end

    context "when the allowlist is unset (fail-closed)" do
      before { ENV.delete(LoginAllowlist::ENV_KEY) }

      let(:denied_claims) { claims }

      it_behaves_like "a denied sign-in", "email_not_listed"
    end

    it "does not touch an existing user's record when the user is no longer allowed" do
      user = User.create!(firebase_uid: "uid_candidate", email: "old@example.com")
      post_sign_in(claims.merge("email" => "stranger@example.net"))

      expect(response).to have_http_status(:forbidden)
      expect(user.reload.email).to eq("old@example.com")
    end
  end

  describe "per-request allowlist re-check" do
    let(:user) { User.create!(firebase_uid: "uid_member", email: "member@example.com", display_name: "Member") }

    before do
      with_allowed_login_emails("member@example.com")
      sign_in_as(user)
    end

    it "keeps the session while the email stays on the list" do
      get dashboard_path
      expect(response).to have_http_status(:ok)
    end

    it "signs the user out on the next request after removal from the list" do
      with_allowed_login_emails("someone-else@example.com")

      expect { get dashboard_path }.to change {
        AuditLog.where(action: AuditLog::ACTION_AUTH_SESSION_REVOKED, user_id: user.id).count
      }.by(1)
      expect(response).to redirect_to(login_path)
      expect(flash[:alert]).to include("招待制")
      expect(session[:user_id]).to be_nil

      # 許可リストに戻しても、セッションは破棄済みなので再ログインが必要
      with_allowed_login_emails("member@example.com")
      get dashboard_path
      expect(response).to redirect_to(login_path)
    end

    it "locks the user out when the list becomes empty" do
      with_allowed_login_emails("")
      get dashboard_path
      expect(response).to redirect_to(login_path)
    end

    it "returns 403 for JSON requests after removal" do
      with_allowed_login_emails("")
      get service_templates_path, as: :json
      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body)["error"]).to eq("not_allowed")
    end

    it "shows the invite-only message on the login page when revoked there" do
      with_allowed_login_emails("")
      get login_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("このサービスは招待制です。このアカウントではログインできません。")
    end
  end

  describe "DELETE /auth/sign_out" do
    it "clears the session" do
      delete auth_sign_out_path, as: :json
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["ok"]).to be(true)
      expect(session[:user_id]).to be_nil
    end
  end

  describe "GET /dashboard (authenticated)" do
    it "redirects to login when not signed in" do
      get dashboard_path
      expect(response).to redirect_to(login_path)
    end
  end
end
