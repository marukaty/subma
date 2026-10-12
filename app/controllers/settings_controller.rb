class SettingsController < ApplicationController
  before_action :authenticate_user!
  # 退会は監査ログを独自に記録する（削除後はユーザーが存在しないため、共通の記録では user を付けられない）
  skip_after_action :record_audit_log, only: :destroy_account

  ACCOUNT_DELETED_MESSAGE = "アカウントとすべてのデータを削除しました。" \
                            "Google アカウントはそのまま残っています。".freeze
  CONFIRMATION_MISMATCH_MESSAGE = "確認用のメールアドレスが一致しません。データは削除していません。".freeze

  def show
    @user = current_user
    load_categories
  end

  def update
    @audit_resource = current_user
    if current_user.update(settings_params)
      redirect_to settings_path, notice: "設定を更新しました"
    else
      @user = current_user
      @categories = {}
      render :show, status: :unprocessable_entity
    end
  end

  # DELETE /settings/account
  # 確認のため、ログイン中のメールアドレスを入力してもらい、一致したときだけ削除する
  def destroy_account
    user = current_user
    request_log = record_account_log(AuditLog::ACTION_ACCOUNT_DELETE_REQUESTED, user: user)

    unless confirmation_matches?(user)
      @user = user
      load_categories
      flash.now[:alert] = CONFIRMATION_MISMATCH_MESSAGE
      return render :show, status: :unprocessable_content
    end

    AccountDeletion.new(
      user: user,
      request_log: request_log,
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    ).call
    Rails.logger.info("[account_deletion] deleted user_id=#{user.id}")

    reset_session
    # ログイン画面でブラウザ側の Firebase のログイン状態も消す（Firebase のアカウントは消さない）
    flash[:account_deleted] = true
    redirect_to login_path, notice: ACCOUNT_DELETED_MESSAGE
  end

  private

  def settings_params
    params.expect(user: [ :notification_enabled ])
  end

  # 利用中サブスクから抽出したカテゴリ一覧
  def load_categories
    @categories = current_user.subscriptions
                              .where.not(category: [ nil, "" ])
                              .group(:category)
                              .order(Arel.sql("COUNT(*) DESC"))
                              .count
  end

  def confirmation_matches?(user)
    input = params[:confirmation_email].to_s.strip
    input.present? && input.casecmp?(user.email.to_s.strip)
  end

  def record_account_log(action, user:)
    AuditLog.create!(
      user: user,
      action: action,
      ip_address: request.remote_ip,
      user_agent: request.user_agent.to_s.first(500)
    )
  rescue StandardError => e
    Rails.logger.error("[audit] failed to record #{action}: #{e.message}")
    nil
  end
end
