# request spec でログイン状態を作るヘルパ。
# FirebaseAuthVerifier だけをスタブし、実際に POST /auth/sign_in を通してセッションを作る。
# current_user をスタブしないので、毎リクエストの許可リスト再判定（ADR-0006）もテストできる。
module SignInHelper
  def firebase_claims_for(user, overrides = {})
    {
      "sub" => user.firebase_uid,
      "email" => user.email,
      "email_verified" => true,
      "name" => user.display_name,
      "firebase" => { "sign_in_provider" => "google.com" }
    }.merge(overrides)
  end

  def stub_firebase_verifier(claims)
    verifier = instance_double(FirebaseAuthVerifier, verify: claims)
    allow(FirebaseAuthVerifier).to receive(:new).and_return(verifier)
  end

  def sign_in_as(user)
    stub_firebase_verifier(firebase_claims_for(user))
    post auth_sign_in_path, params: { id_token: "test.id.token" }, as: :json
    raise "sign_in_as failed: HTTP #{response.status} #{response.body}" unless response.successful?
  end
end

RSpec.configure do |config|
  config.include SignInHelper, type: :request
end
