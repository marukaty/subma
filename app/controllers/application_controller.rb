class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  # テスト環境ではUser-Agentが空で 406 を返してしまうのでスキップ
  allow_browser versions: :modern unless Rails.env.test?

  helper_method :current_user, :user_signed_in?

  private

  def current_user
    return @current_user if defined?(@current_user)

    @current_user = User.find_by(id: session[:user_id])
  end

  def user_signed_in?
    current_user.present?
  end

  def authenticate_user!
    return if user_signed_in?

    respond_to do |format|
      format.html { redirect_to login_path, alert: "ログインしてください" }
      format.json { render json: { error: "unauthorized" }, status: :unauthorized }
    end
  end
end
