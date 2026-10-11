class AuthController < ApplicationController
  # 認証イベントは独自に記録するためグローバルの監査ログをスキップ
  skip_after_action :record_audit_log

  # ログイン画面（未ログインのみアクセス想定。ログイン済みならダッシュボードへ）
  def new
    return redirect_to dashboard_path if user_signed_in?

    # ログイン中に許可リストから外され、このリクエストで締め出された場合
    flash.now[:alert] = INVITE_ONLY_MESSAGE if @session_revoked
  end

  # Firebase Web SDK が取得した ID トークンを受け取り、検証してセッション開始
  # POST /auth/sign_in  body: { id_token: "..." }
  def sign_in
    id_token = params[:id_token].to_s
    claims = FirebaseAuthVerifier.new.verify(id_token)

    # 許可リスト判定は User を作る前に行う（拒否した人の User 行を残さない）
    decision = LoginAllowlist.check(claims)
    return deny_sign_in(claims, decision.reason) unless decision.allowed?

    user = User.from_firebase_claims(claims)
    reset_session
    session[:user_id] = user.id
    record_auth_log(AuditLog::ACTION_AUTH_SIGN_IN, user: user)
    render json: { ok: true, redirect_to: dashboard_path }
  rescue FirebaseAuthVerifier::InvalidTokenError => e
    Rails.logger.warn("[auth] invalid token: #{e.message}")
    record_auth_log(AuditLog::ACTION_AUTH_SIGN_IN_FAILED, user: nil)
    render json: { ok: false, error: "invalid_token" }, status: :unauthorized
  end

  # DELETE /auth/sign_out
  def sign_out
    user_before = current_user
    reset_session
    record_auth_log(AuditLog::ACTION_AUTH_SIGN_OUT, user: user_before)
    respond_to do |format|
      format.json { render json: { ok: true, redirect_to: login_path } }
      format.html { redirect_to login_path }
    end
  end

  private

  def deny_sign_in(claims, reason)
    reset_session
    Rails.logger.warn(
      "[auth] sign-in denied reason=#{reason} email=#{LoginAllowlist.mask_email(claims["email"])}"
    )
    record_auth_log(AuditLog::ACTION_AUTH_SIGN_IN_DENIED, user: nil)
    render json: { ok: false, error: "not_allowed", message: INVITE_ONLY_MESSAGE }, status: :forbidden
  end

  def record_auth_log(action, user:)
    AuditLog.create!(
      user: user,
      action: action,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(500)
    )
  rescue StandardError => e
    Rails.logger.error("[audit] failed to record auth log #{action}: #{e.message}")
  end
end
