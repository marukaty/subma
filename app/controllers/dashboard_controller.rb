class DashboardController < ApplicationController
  before_action :authenticate_user!

  def show
    # Phase 2 で実装。現状は空のダッシュボード（ログイン確認用）
  end
end
