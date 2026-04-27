Rails.application.routes.draw do
  # ヘルスチェック
  get "up" => "rails/health#show", as: :rails_health_check

  # 認証
  get  "login"          => "auth#new",      as: :login
  post "auth/sign_in"   => "auth#sign_in",  as: :auth_sign_in
  delete "auth/sign_out" => "auth#sign_out", as: :auth_sign_out

  # ダッシュボード
  get "dashboard" => "dashboard#show", as: :dashboard

  # サブスク CRUD
  resources :subscriptions, except: [ :show ] do
    member do
      patch :pause     # active -> paused
      patch :resume    # paused -> active
      patch :cancel    # -> cancelled
    end
  end

  # ServiceTemplate（プルダウン用 JSON）
  resources :service_templates, only: [ :index ]

  # 設定
  resource :settings, only: [ :show, :update ]

  # ルート
  root to: redirect { |_, req|
    # NOTE: redirect の中で session を直接見る方法はないため、
    # ApplicationController の root へ寄せる方が正攻法だが、シンプル運用として
    # 未ログインなら /login、ログイン済みなら /dashboard へ静的に振り分けるのは
    # 後の Phase 2 で対応。ここでは /dashboard へ送り、認証必須で /login にリダイレクト。
    "/dashboard"
  }
end
