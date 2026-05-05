# Cloud Scheduler ジョブ定義（Phase 5 以降の v2 用、PR-B では枠だけ作る）
#
# 用途（v2 で実装予定）:
#   - 引落リマインドメール（毎朝 9:00 JST、当月引落予定のサブスクをユーザーに通知）
#   - subscription の next_billing_date を月次更新するバッチ
#
# 本 PR では枠（コメントアウト相当のコメント）だけ。実ジョブは v2 で追加。
#
# [ai-assisted]

# ---------- v2 で追加予定のスケッチ ----------
#
# resource "google_cloud_scheduler_job" "billing_reminder" {
#   name        = "billing-reminder"
#   description = "毎朝 9:00 JST に当月引落予定のサブスクをユーザーに通知"
#   schedule    = "0 9 * * *"
#   time_zone   = "Asia/Tokyo"
#   region      = var.region
#
#   http_target {
#     http_method = "POST"
#     uri         = "${google_cloud_run_v2_service.web.uri}/internal/jobs/send_billing_reminders"
#
#     oidc_token {
#       service_account_email = google_service_account.cloud_tasks.email
#       audience              = "${google_cloud_run_v2_service.web.uri}/internal/jobs/send_billing_reminders"
#     }
#   }
#
#   depends_on = [google_project_service.required_apis]
# }

# ----- placeholder data source として API 有効化のみ確認しておく -----
# Cloud Scheduler API は main.tf で有効化済み。本ファイルは v2 着手時のドラフト保存場所。
