class AuthController < ApplicationController
  # ログイン画面（未ログインのみアクセス想定。ログイン済みならダッシュボードへ）
  def new
    redirect_to dashboard_path if user_signed_in?
  end

  # Firebase Web SDK が取得した ID トークンを受け取り、検証してセッション開始
  # POST /auth/sign_in  body: { id_token: "..." }
  def sign_in
    id_token = params[:id_token].to_s
    claims = FirebaseAuthVerifier.new.verify(id_token)
    user = User.from_firebase_claims(claims)
    reset_session
    session[:user_id] = user.id
    render json: { ok: true, redirect_to: dashboard_path }
  rescue FirebaseAuthVerifier::InvalidTokenError => e
    Rails.logger.warn("[auth] invalid token: #{e.message}")
    render json: { ok: false, error: "invalid_token" }, status: :unauthorized
  end

  # DELETE /auth/sign_out
  def sign_out
    reset_session
    respond_to do |format|
      format.json { render json: { ok: true, redirect_to: login_path } }
      format.html { redirect_to login_path }
    end
  end
end
