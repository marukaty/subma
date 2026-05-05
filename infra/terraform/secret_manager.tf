# Secret Manager 上の秘密値定義
#
# 格納する Secret:
#   - rails-master-key       : Rails の credentials 復号キー
#   - anthropic-api-key      : Claude API キー
#   - firebase-web-api-key   : Firebase Web SDK の apiKey
#   - cloud-sql-app-password : Cloud SQL のアプリ用ユーザーパスワード（random_password）
#
# 各 Secret には Cloud Run SA に対して accessor 権限を付与。
# Cloud Run service の env では `value_source.secret_key_ref` でこの Secret を参照する。
#
# [ai-assisted]

# ===================================================================
# 共通: secret 作成 + Cloud Run SA への accessor 権限付与
# ===================================================================

locals {
  secrets = {
    "rails-master-key"       = var.rails_master_key
    "anthropic-api-key"      = var.anthropic_api_key
    "firebase-web-api-key"   = var.firebase_web_api_key
    "cloud-sql-app-password" = random_password.cloud_sql_app.result
  }
}

resource "google_secret_manager_secret" "subma" {
  for_each = local.secrets

  secret_id = each.key

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_version" "subma" {
  for_each = local.secrets

  secret      = google_secret_manager_secret.subma[each.key].id
  secret_data = each.value
}

# Cloud Run SA が各 secret にアクセスできるようにする
resource "google_secret_manager_secret_iam_member" "cloud_run_accessor" {
  for_each = local.secrets

  secret_id = google_secret_manager_secret.subma[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}
