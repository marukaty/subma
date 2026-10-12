# Cloud Tasks からの HTTP push を受信して非同期ジョブを実行するエンドポイント
#
# 設計:
#   - Cloud Tasks → Cloud Run (本コントローラ) に POST が飛ぶ
#   - Authorization: Bearer <id_token> を OidcVerifier で検証
#     （aud = CLOUD_TASKS_TARGET_URL、発行元 email = CLOUD_TASKS_SA_EMAIL）
#   - 検証が通れば ProcessCsvJob を **同期実行**（Sidekiq を経由しない、Cloud Run プロセス内）
#   - Cloud Tasks のタイムアウト・リトライ機構に処理時間と配送の失敗を任せる
#   - 処理済み・処理中・失敗済みの import はジョブ側で何もせず 200 を返す（ADR-0007）。
#     Cloud Tasks の再送（at-least-once 配信）で同じ import を二重に処理しないため
#
# セキュリティ:
#   - CSRF 検証はスキップ（Cloud Tasks は CSRF トークンを送れない）
#   - 監査ログはスキップ（ユーザーアクションではないため）
#   - ENABLE_OIDC_VERIFICATION=true（または production）で OIDC 検証必須
#   - dev / test の手動疎通確認用に OIDC 検証を環境変数でオフにできる
#
# [ai-assisted]
module Internal
  class JobsController < ApplicationController
    skip_before_action :verify_authenticity_token, raise: false
    skip_after_action :record_audit_log, raise: false
    before_action :verify_oidc_token!

    # POST /internal/jobs/process_csv
    # Body: { "csv_import_id": <integer> }
    def process_csv
      csv_import_id = params[:csv_import_id]
      if csv_import_id.blank?
        render json: { error: "csv_import_id is required" }, status: :bad_request
        return
      end

      # Cloud Tasks から呼ばれた場合は同期実行（Cloud Tasks がタイムアウト管理）
      result = ProcessCsvJob.new.perform(csv_import_id.to_i)

      render json: { ok: true, csv_import_id: csv_import_id.to_i, result: result }
    end

    private

    def verify_oidc_token!
      return if oidc_verification_disabled?

      token = extract_bearer_token
      if token.blank?
        render json: { error: "missing bearer token" }, status: :unauthorized
        return
      end

      audience = required_env("CLOUD_TASKS_TARGET_URL")
      expected_email = required_env("CLOUD_TASKS_SA_EMAIL")
      OidcVerifier.new(audience: audience, expected_email: expected_email).verify(token)
    rescue OidcVerifier::InvalidTokenError => e
      Rails.logger.warn("[Internal::JobsController] OIDC verify failed: #{e.message}")
      render json: { error: "invalid token" }, status: :unauthorized
    rescue KeyError => e
      Rails.logger.error("[Internal::JobsController] missing env: #{e.message}")
      render json: { error: "server misconfigured" }, status: :internal_server_error
    end

    # 未設定・空文字はどちらも設定不備として扱い、検証を通さない（fail-closed）
    def required_env(key)
      ENV[key].presence || raise(KeyError, "#{key} is not set")
    end

    def extract_bearer_token
      auth_header = request.headers["Authorization"].to_s
      return nil unless auth_header.start_with?("Bearer ")

      auth_header.sub("Bearer ", "")
    end

    # production では常に検証する。
    # dev / test では ENABLE_OIDC_VERIFICATION=true で明示的に有効化したときだけ検証する。
    def oidc_verification_disabled?
      return false if Rails.env.production?

      ENV["ENABLE_OIDC_VERIFICATION"] != "true"
    end
  end
end
