# request spec で current_user を擬似的にセットするヘルパ
# Firebase JWT 検証をモックして直接 session に user_id を入れる方法は難しいため、
# ApplicationController#current_user を直接スタブする方式
module SignInHelper
  def sign_in_as(user)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:user_signed_in?).and_return(true)
  end
end

RSpec.configure do |config|
  config.include SignInHelper, type: :request
end
