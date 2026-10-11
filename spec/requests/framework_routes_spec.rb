require "rails_helper"

# 使っていないフレームワークの公開エンドポイントが無効になっていることを確認する
RSpec.describe "Framework routes", type: :request do
  def route_exists?(method, path)
    Rails.application.routes.recognize_path(path, method: method)
    true
  rescue ActionController::RoutingError
    false
  end

  it "does not expose Active Storage direct upload / disk / blob routes" do
    expect(route_exists?(:post, "/rails/active_storage/direct_uploads")).to be(false)
    expect(route_exists?(:put, "/rails/active_storage/disk/token")).to be(false)
    expect(route_exists?(:get, "/rails/active_storage/disk/key/file.csv")).to be(false)
    expect(route_exists?(:get, "/rails/active_storage/blobs/redirect/sid/file.csv")).to be(false)
  end

  it "does not expose Action Mailbox ingress routes" do
    expect(route_exists?(:post, "/rails/action_mailbox/relay/inbound_emails")).to be(false)
    expect(route_exists?(:get, "/rails/conductor/action_mailbox/inbound_emails")).to be(false)
  end

  it "does not load unused frameworks" do
    expect(defined?(ActionMailbox::Engine)).to be_nil
    expect(defined?(ActionText::Engine)).to be_nil
    expect(defined?(ActionCable::Engine)).to be_nil
  end

  it "keeps the session cookie expiring with SameSite=Lax" do
    options = Rails.application.config.session_options
    expect(options[:expire_after]).to eq(12.hours)
    expect(options[:same_site]).to eq(:lax)
  end
end
