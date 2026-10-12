require "rails_helper"

# レート制限のキーが、Rails の remote_ip と同じ「信頼する中継を除いたクライアント IP」になることを確認する。
# Cloud Run ではコンテナから見た REMOTE_ADDR がリンクローカル（169.254.x.x）になるので、その前提で送る。
RSpec.describe "Rack::Attack", type: :request do
  let(:cloud_run_peer) { "169.254.1.1" }

  # test 環境の cache_store は :null_store で数えられないため、この spec の間だけメモリに数える
  around do |example|
    original_store = Rack::Attack.cache.store
    Rack::Attack.cache.store = ActiveSupport::Cache::MemoryStore.new
    Rack::Attack.reset!
    example.run
  ensure
    Rack::Attack.cache.store = original_store
  end

  before do
    verifier = instance_double(FirebaseAuthVerifier)
    allow(verifier).to receive(:verify).and_raise(FirebaseAuthVerifier::InvalidTokenError, "bad token")
    allow(FirebaseAuthVerifier).to receive(:new).and_return(verifier)
  end

  def via_cloud_run(forwarded_for)
    { headers: { "X-Forwarded-For" => forwarded_for }, env: { "REMOTE_ADDR" => cloud_run_peer } }
  end

  def post_sign_in(forwarded_for)
    post auth_sign_in_path, params: { id_token: "bad.token" }, as: :json, **via_cloud_run(forwarded_for)
  end

  # Rack::Attack が request.env に残す、各制限のキー（discriminator）
  def throttle_key(name)
    request.env.fetch("rack.attack.throttle_data").fetch(name)[:discriminator]
  end

  describe "制限のキー" do
    it "全体の制限は X-Forwarded-For の転送元 IP をキーにする（REMOTE_ADDR の 169.254.x.x ではない）" do
      get login_path, **via_cloud_run("203.0.113.10")

      expect(throttle_key("requests by ip")).to eq("203.0.113.10")
    end

    it "ログインの制限は転送元 IP をキーにする" do
      post_sign_in("203.0.113.10")

      expect(throttle_key("auth sign_in by ip")).to eq("203.0.113.10")
    end

    it "CSV 取り込みの制限は転送元 IP をキーにする" do
      post csv_imports_path, **via_cloud_run("203.0.113.10")

      expect(throttle_key("csv upload by ip")).to eq("203.0.113.10")
    end

    it "X-Forwarded-For の左側に偽の IP を入れても、右端（中継が付けた）の IP をキーにする" do
      get login_path, **via_cloud_run("198.51.100.99, 203.0.113.10")

      expect(throttle_key("requests by ip")).to eq("203.0.113.10")
    end
  end

  describe "POST /auth/sign_in（同じ IP から 1 分に 5 回まで）" do
    it "転送元 IP ごとに数え、上限を超えた IP だけを 429 にする" do
      5.times do
        post_sign_in("203.0.113.10")
        expect(response).to have_http_status(:unauthorized)
      end

      post_sign_in("203.0.113.10")
      expect(response).to have_http_status(:too_many_requests)

      # 同じ Cloud Run の中継（169.254.x.x）を通っていても、別のクライアントは制限されない
      post_sign_in("203.0.113.20")
      expect(response).to have_http_status(:unauthorized)
    end

    it "X-Forwarded-For の左側を書き換えても制限を回避できない" do
      5.times { post_sign_in("203.0.113.10") }

      post_sign_in("198.51.100.99, 203.0.113.10")
      expect(response).to have_http_status(:too_many_requests)
    end
  end
end
