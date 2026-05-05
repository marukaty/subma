# Phase 4: Cloud Tasks からの HTTP push を受信して非同期ジョブを実行するエンドポイント
#
# 設計:
#   - Cloud Tasks → Cloud Run (本コントローラ) に POST が飛ぶ
#   - Authorization: Bearer <id_token> を OidcVerifier で検証
#   - 検証が通れば ProcessCsvJob を **同期実行**（Sidekiq を経由しない、Cloud Run プロセス内）
#   - Cloud Tasks のタイムアウト・リトライ機構に処理時間とエラー処理を任せる
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
      ProcessCsvJob.new.perform(csv_import_id.to_i)

      render json: { ok: true, csv_import_id: csv_import_id.to_i }
    end

    private

    def verify_oidc_token!
      return if oidc_verification_disabled?

      token = extract_bearer_token
      if token.blank?
        render json: { error: "missing bearer token" }, status: :unauthorized
        return
      end

      audience = ENV.fetch("CLOUD_TASKS_TARGET_URL")
      OidcVerifier.new(audience: audience).verify(token)
    rescue OidcVerifier::InvalidTokenError => e
      Rails.logger.warn("[Internal::JobsController] OIDC verify failed: #{e.message}")
      render json: { error: "invalid token" }, status: :unauthorized
    rescue KeyError => e
      Rails.logger.error("[Internal::JobsController] missing env: #{e.message}")
      render json: { error: "server misconfigured" }, status: :internal_server_error
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
