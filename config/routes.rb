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

  # CSV 取り込み
  resources :csv_imports, only: [ :index, :new, :create, :show ] do
    member do
      post :register  # 取り込み結果の確認 → Subscription 一括登録
    end
    # 失敗した取り込みの再処理（ADR-0007）
    resource :retry, only: [ :create ], module: :csv_imports
  end

  # 設定
  resource :settings, only: [ :show, :update ]
  # 退会（アカウントとすべてのデータを削除）
  delete "settings/account" => "settings#destroy_account", as: :settings_account

  # Cloud Tasks からの HTTP push 受信エンドポイント（OIDC 検証必須）
  namespace :internal do
    post "jobs/process_csv" => "jobs#process_csv", as: :jobs_process_csv
  end

  # ルート
  root to: redirect { |_, req|
    # redirect の中では session を見られないため、常に /dashboard へ送る。
    # 未ログインなら /dashboard の認証で /login にリダイレクトされる。
    "/dashboard"
  }
end
