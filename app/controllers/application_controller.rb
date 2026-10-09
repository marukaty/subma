class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # テスト環境ではUser-Agentが空で 406 を返してしまうのでスキップ
  allow_browser versions: :modern unless Rails.env.test?

  # Lograge にユーザー識別子・リクエスト ID を渡す
  def append_info_to_payload(payload)
    super
    payload[:user_id] = current_user&.id
    payload[:request_id] = request.request_id
    payload[:remote_ip] = request.remote_ip
  end

  helper_method :current_user, :user_signed_in?

  # 許可リスト（ADR-0006）で拒否・締め出したときに表示する文言
  INVITE_ONLY_MESSAGE = "このサービスは招待制です。このアカウントではログインできません。".freeze

  # 全書き込み操作で監査ログを記録（NFR-S-05）
  # GET 以外（POST / PATCH / PUT / DELETE）が対象
  # サブクラスで個別記録したい場合は skip_after_action :record_audit_log で除外
  after_action :record_audit_log, if: :should_audit_log?

  private

  def should_audit_log?
    !request.get? && !request.head?
  end

  def record_audit_log
    AuditLog.create!(
      user: current_user,
      action: "#{controller_name}.#{action_name}",
      resource_type: @audit_resource&.class&.name,
      resource_id: @audit_resource&.id,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(500)
    )
  rescue StandardError => e
    # 監査ログの失敗で本処理を巻き込まない（ログだけ残す）
    Rails.logger.error("[audit] failed to record audit log: #{e.message}")
  end

  # セッションのユーザーを解決する。
  # 毎リクエスト許可リストを再判定し、許可を外されたユーザーはセッションを破棄して締め出す（ADR-0006）
  def current_user
    return @current_user if defined?(@current_user)

    user = session[:user_id].present? ? User.find_by(id: session[:user_id]) : nil
    if user && !LoginAllowlist.allowed_email?(user.email)
      revoke_session!(user)
      user = nil
    end

    @current_user = user
  end

  def revoke_session!(user)
    reset_session
    @session_revoked = true
    Rails.logger.warn(
      "[auth] session revoked (not in allowlist) user_id=#{user.id} email=#{LoginAllowlist.mask_email(user.email)}"
    )
    AuditLog.create!(
      user: user,
      action: AuditLog::ACTION_AUTH_SESSION_REVOKED,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(500)
    )
  rescue StandardError => e
    Rails.logger.error("[audit] failed to record session revocation: #{e.message}")
  end

  def user_signed_in?
    current_user.present?
  end

  def authenticate_user!
    return if user_signed_in?

    if @session_revoked
      respond_to do |format|
        format.html { redirect_to login_path, alert: INVITE_ONLY_MESSAGE }
        format.json { render json: { error: "not_allowed" }, status: :forbidden }
      end
      return
    end

    respond_to do |format|
      format.html { redirect_to login_path, alert: "ログインしてください" }
      format.json { render json: { error: "unauthorized" }, status: :unauthorized }
    end
  end
end
