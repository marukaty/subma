# Secret Manager 上の秘密値定義
#
# 格納する Secret:
#   - rails-master-key       : Rails の credentials 復号キー
#   - anthropic-api-key      : Claude API キー
#   - firebase-web-api-key   : Firebase Web SDK の apiKey
#   - cloud-sql-app-password : Cloud SQL のアプリ用ユーザーパスワード（random_password）
#   - allowed-login-emails   : ログイン許可リスト（ADR-0006）
#
# 方針: Terraform は Secret の「器」と Cloud Run SA の accessor 権限だけを管理し、
# 外部から持ち込む値（API キー等）は Terraform の変数・tfvars・tfstate に入れない。
# 値は運用者が gcloud で帯域外に投入する（手順: docs/infrastructure-notes.md 8.9）:
#
#   gcloud secrets versions add anthropic-api-key --data-file=-
#
# 理由:
#   - tfstate には secret_data が平文で残る。state バケットの閲覧権限 = 全 Secret の閲覧権限になってしまう
#   - Terraform が secret_version を管理していると、手で無効化した版を次の apply で有効に戻してしまう
#     （鍵のローテーションや漏洩時の失効と衝突する）
#
# 例外: cloud-sql-app-password は Terraform 自身が random_password で生成し、google_sql_user にも
# 同じ値を設定している。値の出どころが Terraform なので版も Terraform が管理し、DB ユーザーと
# Secret の値がずれないようにする（この値は google_sql_user / random_password として state に残る）。
#
# Cloud Run service / job の env では `value_source.secret_key_ref`（version = "latest"）で参照する。
#
# [ai-assisted]

# ===================================================================
# 共通: secret 作成 + Cloud Run SA への accessor 権限付与
# ===================================================================

locals {
  secret_ids = toset([
    "rails-master-key",
    "anthropic-api-key",
    "firebase-web-api-key",
    "cloud-sql-app-password",
  ])
}

resource "google_secret_manager_secret" "subma" {
  for_each = local.secret_ids

  secret_id = each.key

  replication {
    auto {}
  }

  labels = local.common_labels

  depends_on = [google_project_service.required_apis]
}

# Cloud Run SA が各 secret にアクセスできるようにする
resource "google_secret_manager_secret_iam_member" "cloud_run_accessor" {
  for_each = local.secret_ids

  secret_id = google_secret_manager_secret.subma[each.key].id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.cloud_run.email}"
}

# DB パスワードの版だけは Terraform が管理する（上記「例外」参照）
resource "google_secret_manager_secret_version" "cloud_sql_app_password" {
  secret      = google_secret_manager_secret.subma["cloud-sql-app-password"].id
  secret_data = random_password.cloud_sql_app.result
}

# 以前は google_secret_manager_secret_version.subma[*] で全 Secret の版を Terraform が作っていた。
# DB パスワードの版は上のリソースへアドレスだけ移す（作り直さない）。
moved {
  from = google_secret_manager_secret_version.subma["cloud-sql-app-password"]
  to   = google_secret_manager_secret_version.cloud_sql_app_password
}

# 残りの版（rails-master-key / anthropic-api-key / firebase-web-api-key）は state からだけ外す。
# destroy = false なので GCP 上の版は削除・無効化されずに残り、Cloud Run は引き続き読める。
# 以後の版の追加・無効化は gcloud で行い、Terraform は関与しない。
removed {
  from = google_secret_manager_secret_version.subma

  lifecycle {
    destroy = false
  }
}

# ===================================================================
# ログイン許可リスト（ADR-0006）
# ===================================================================
#
# 許可するメールアドレスは個人情報なので、Terraform の変数・tfvars・tfstate に入れない。
# ここでは Secret の器と accessor 権限だけを作り、secret_version は作らない。
# 値は次のように帯域外で投入する（手順の詳細: docs/infrastructure-notes.md 8.5）:
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
