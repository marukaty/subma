# Cloud Tasks Queue 定義
#
# 設計:
#   - キュー名 process-csv: CSV 取り込みジョブ用
#   - 並列度 max_dispatches_per_second = 1（コスト節約 + AI rate limit 配慮）
#   - 同時実行 max_concurrent_dispatches = 2。1 件で最長 15 分 Puma のスレッドを占有するため、
#     ジョブが Web のリクエストを処理するスレッドを使い切らないように絞る（ADR-0007）
#   - リトライ設定: 最大 3 回、指数バックオフ（10 秒 → 最大 300 秒）。
#     再送はおもに配送の失敗（インスタンス停止・5xx）向け。同じ import の再送はジョブ側の
#     状態ガードで何もせず 200 を返すので、AI の二重呼び出しにはならない
#   - 1 回の待ち時間（dispatch_deadline）はタスク作成時に 900 秒を指定（Cloud Run の timeout と同じ）
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
    max_concurrent_dispatches = 2
  }

  retry_config {
    max_attempts       = 3
    min_backoff        = "10s"
    max_backoff        = "300s"
    max_doublings      = 4
    max_retry_duration = "1800s" # 最初の試行から 30 分たったら再送を打ち切る
  }

  depends_on = [google_project_service.required_apis]
}

output "cloud_tasks_queue" {
  description = "Cloud Tasks queue 名（CsvProcessingDispatcher の ENV で使う）"
  value       = google_cloud_tasks_queue.process_csv.name
}
