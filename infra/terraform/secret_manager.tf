# Secret Manager 上の秘密値定義
#
# 格納する Secret:
#   - rails-master-key       : Rails の credentials 復号キー
#   - anthropic-api-key      : Claude API キー
#   - firebase-web-api-key   : Firebase Web SDK の apiKey
#   - cloud-sql-app-password : Cloud SQL のアプリ用ユーザーパスワード（random_password）
#   - allowed-login-emails   : ログイン許可リスト（ADR-0006）。器だけ Terraform で作り、
#                              値は gcloud で帯域外投入する（後述）
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

# ===================================================================
# ログイン許可リスト（ADR-0006）
# ===================================================================
#
# 許可するメールアドレスは個人情報なので、Terraform の変数・tfvars・tfstate に入れない。
# ここでは Secret の器と accessor 権限だけを作り、secret_version は作らない。
# 値は次のように帯域外で投入する（手順の詳細: docs/infrastructure-notes.md 8.4）:
#
#   printf '%s' 'a@example.com,b@example.com' | \
#     gcloud secrets versions add allowed-login-emails --data-file=-
#
# 値が無い（または空）のまま Cloud Run から参照すると起動に失敗するか全員拒否になる（fail-closed）。

resource "google_secret_manager_secret" "allowed_login_emails" {
  secret_id = "allowed-login-emails"

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret_iam_member" "allowed_login_emails_accessor" {
  secret_id = google_secret_manager_secret.allowed_login_emails.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}
