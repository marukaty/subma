class SettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    # 利用中サブスクから抽出したカテゴリ一覧
    @categories = current_user.subscriptions
                              .where.not(category: [ nil, "" ])
                              .group(:category)
                              .order(Arel.sql("COUNT(*) DESC"))
                              .count
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

  private

  def settings_params
    params.expect(user: [ :notification_enabled ])
  end
end
