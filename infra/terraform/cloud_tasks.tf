# Cloud Tasks Queue 定義
#
# 設計:
#   - キュー名 process-csv: CSV 取り込みジョブ用
#   - 並列度 max_dispatches_per_second = 1（コスト節約 + AI rate limit 配慮）
#   - リトライ設定: 最大 3 回、指数バックオフ
#   - HTTP push のターゲットは Cloud Run の Internal::JobsController#process_csv
#     （Cloud Run service の URL は cloud_run.tf の output から取得）
#
# OIDC 認証は CsvProcessingDispatcher 側で task 作成時に oidc_token フィールドで指定する。
# キューレベルでは認証を強制しない。
#
# [ai-assisted]

resource "google_cloud_tasks_queue" "process_csv" {
  name     = "process-csv"
  location = var.region

  rate_limits {
    max_dispatches_per_second = 1
    max_concurrent_dispatches = 5
  }

  retry_config {
    max_attempts       = 3
    min_backoff        = "10s"
    max_backoff        = "300s"
    max_doublings      = 4
    max_retry_duration = "1800s" # 30 分（Cloud Tasks の HTTP push 上限）
  }

  depends_on = [google_project_service.required_apis]
}

output "cloud_tasks_queue" {
  description = "Cloud Tasks queue 名（CsvProcessingDispatcher の ENV で使う）"
  value       = google_cloud_tasks_queue.process_csv.name
}
