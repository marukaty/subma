# ALLOWED_LOGIN_EMAILS を example ごとに退避・復元する。
# 既定は "*"（test 環境でのみ全員許可。production では無視される / ADR-0006）。
# 許可リストの挙動を確かめる example では with_allowed_login_emails で上書きする。
module LoginAllowlistEnvHelper
  def with_allowed_login_emails(value)
    ENV[LoginAllowlist::ENV_KEY] = value
  end
end

RSpec.configure do |config|
  config.include LoginAllowlistEnvHelper

  config.around do |example|
    original = ENV.fetch(LoginAllowlist::ENV_KEY, nil)
    ENV[LoginAllowlist::ENV_KEY] = LoginAllowlist::WILDCARD
    example.run
  ensure
    if original.nil?
      ENV.delete(LoginAllowlist::ENV_KEY)
    else
      ENV[LoginAllowlist::ENV_KEY] = original
    end
  end
end
