# Service Account 定義 + Workload Identity Federation
#
# 設計:
#   - cloud_run_sa: Cloud Run のランタイム ID。最小権限のみ付与:
#       - Cloud SQL Client（接続）
#       - Secret Manager Secret Accessor（秘密値読み取り）
#       - Cloud Storage Object Admin（CSV 一時バケットのみ）
#       - Cloud Tasks Enqueuer（タスク投入）
#   - cloud_tasks_sa: Cloud Tasks が OIDC トークンを発行する SA。
#     Cloud Run の subma-web service に対して roles/run.invoker を持つ。
#   - deployer_sa: GitHub Actions（Workload Identity Federation 経由）が assume する SA。
#     Cloud Run / Cloud SQL / Secret Manager / Artifact Registry の管理権限を持つ。
#
# [ai-assisted]

# ===================================================================
# Cloud Run ランタイム SA
# ===================================================================

resource "google_service_account" "cloud_run" {
  account_id   = "${var.app_name}-run"
  display_name = "SubMa Cloud Run runtime"
  description  = "Cloud Run の subma-web サービスが利用するランタイム SA"
}

resource "google_project_iam_member" "cloud_run_sql_client" {
  project = var.project_id
  role    = "roles/cloudsql.client"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

resource "google_project_iam_member" "cloud_run_tasks_enqueuer" {
  project = var.project_id
  role    = "roles/cloudtasks.enqueuer"
  member  = "serviceAccount:${google_service_account.cloud_run.email}"
}

# Cloud Storage はバケット単位で IAM を付ける（プロジェクト全体ではなく最小権限）
# → cloud_storage.tf 内で google_storage_bucket_iam_member として付与

# ===================================================================
# Cloud Tasks 用 SA（OIDC トークン発行元）
# ===================================================================

resource "google_service_account" "cloud_tasks" {
  account_id   = "${var.app_name}-tasks"
  display_name = "SubMa Cloud Tasks invoker"
  description  = "Cloud Tasks が OIDC トークンを発行して Cloud Run を叩くための SA"
}

# Cloud Tasks SA が Cloud Run を invoke できるようにする。
# Cloud Run service が作成された後に紐づけるため、cloud_run.tf 側で google_cloud_run_v2_service_iam_member として付与。

# ===================================================================
# デプロイ用 SA（GitHub Actions OIDC 経由で assume）
# ===================================================================

resource "google_service_account" "deployer" {
  account_id   = "${var.app_name}-deployer"
  display_name = "SubMa CI/CD deployer"
  description  = "GitHub Actions が Workload Identity Federation 経由で assume する SA"
}

# デプロイ SA に必要な最小権限の集合:
#   - Cloud Run 管理
#   - Cloud SQL 管理（インスタンス操作）
#   - Secret Manager 管理（バージョン追加）
#   - Artifact Registry へのイメージ push
#   - Service Account Token 発行（Cloud Run へのデプロイ時に他 SA を使うため）
locals {
  deployer_roles = [
    "roles/run.admin",
    "roles/cloudsql.admin",
    "roles/secretmanager.admin",
    "roles/artifactregistry.writer",
    "roles/iam.serviceAccountUser",
    "roles/storage.admin",
  ]
}

resource "google_project_iam_member" "deployer_roles" {
  for_each = toset(local.deployer_roles)

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# ===================================================================
# Workload Identity Federation（GitHub Actions → GCP）
# ===================================================================
# GitHub Actions が長期 SA キー JSON を持たずに GCP に認証するための仕組み。
# pool 1 つ + provider 1 つ + binding（特定リポジトリの workflow からのみ assume を許可）。

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "${var.app_name}-github-pool"
  display_name              = "GitHub Actions"
  description               = "GitHub Actions OIDC pool for ${var.github_repository}"

  depends_on = [google_project_service.required_apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-actions"
  display_name                       = "GitHub Actions OIDC"
  description                        = "GitHub Actions OIDC provider"

  attribute_mapping = {
    "google.subject"             = "assertion.sub"
    "attribute.repository"       = "assertion.repository"
    "attribute.repository_owner" = "assertion.repository_owner"
    "attribute.ref"              = "assertion.ref"
  }

  # 特定の GitHub リポジトリからのみ assume 可能にする
  attribute_condition = "assertion.repository == '${var.github_repository}'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# WIF pool の identity が deployer SA を assume できるようにする
resource "google_service_account_iam_member" "wif_deployer" {
  service_account_id = google_service_account.deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repository}"
}

# ===================================================================
# 出力
# ===================================================================

output "cloud_run_service_account" {
  description = "Cloud Run runtime SA email"
  value       = google_service_account.cloud_run.email
}

output "cloud_tasks_service_account" {
  description = "Cloud Tasks SA email"
  value       = google_service_account.cloud_tasks.email
}

output "deployer_service_account" {
  description = "Deployer SA email（GitHub Actions WIF 経由で assume する）"
  value       = google_service_account.deployer.email
}

output "workload_identity_provider" {
  description = "GitHub Actions WIF provider 名（GitHub Secrets に登録する）"
  value       = google_iam_workload_identity_pool_provider.github.name
}
