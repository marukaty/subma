# Cloud Storage バケット（CSV 一時保存用）
#
# 設計（NFR-S-09 準拠）:
#   - CSV は処理後すぐ purge されるが、念のため**1 日後に自動削除** を設定
#   - バージョニング無効（一時ファイルなので）
#   - パブリックアクセス禁止
#   - Cloud Run SA のみが読み書きできる
#
# 本番の Active Storage の保存先（config/storage.yml の google。バケット名は環境変数 CSV_TEMP_BUCKET）。
#
# [ai-assisted]

resource "google_storage_bucket" "csv_temp" {
  name          = "${var.project_id}-${var.app_name}-csv-temp"
  location      = var.region
  storage_class = "STANDARD"

  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"

  # 1 日後に自動削除（NFR-S-09: CSV を残さない）
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "Delete"
    }
  }

  # 不完全マルチパートアップロードも 1 日で消す
  lifecycle_rule {
    condition {
      age = 1
    }
    action {
      type = "AbortIncompleteMultipartUpload"
    }
  }

  versioning {
    enabled = false
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Run SA にバケット内オブジェクトの読み書き権限を付与（バケット単位の最小権限）
resource "google_storage_bucket_iam_member" "cloud_run_csv_temp_object_admin" {
  bucket = google_storage_bucket.csv_temp.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.cloud_run.email}"
}

output "csv_temp_bucket" {
  description = "CSV 一時保存バケット名"
  value       = google_storage_bucket.csv_temp.name
}
