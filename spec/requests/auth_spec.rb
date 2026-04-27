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
      # Sessions can't be set directly in request specs without warden/devise
      # so we go through sign_in path. Instead, verify the redirect logic
      # by stubbing current_user.
      allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
      get login_path
      expect(response).to redirect_to(dashboard_path)
    end
  end

  describe "POST /auth/sign_in" do
    let(:claims) { { "sub" => "uid_new", "email" => "new@example.com", "name" => "New User" } }

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
