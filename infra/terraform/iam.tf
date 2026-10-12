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
#     deploy.yml が実際に行う操作（イメージ push、Cloud Run service / job の更新と実行）に
#     必要な権限だけを持つ。Cloud SQL / Secret Manager / Cloud Storage の権限は持たない。
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

# Cloud Run runtime SA が Cloud Tasks に「subma-tasks SA で OIDC トークン発行して」と頼めるようにする。
# これがないと enqueue 時に PermissionDenied (iam.serviceAccounts.actAs) が出る。
resource "google_service_account_iam_member" "cloud_run_uses_cloud_tasks_sa" {
  service_account_id = google_service_account.cloud_tasks.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.cloud_run.email}"
}

# ===================================================================
# デプロイ用 SA（GitHub Actions OIDC 経由で assume）
# ===================================================================

resource "google_service_account" "deployer" {
  account_id   = "${var.app_name}-deployer"
  display_name = "SubMa CI/CD deployer"
  description  = "GitHub Actions が Workload Identity Federation 経由で assume する SA"
}

# デプロイ SA の権限は .github/workflows/deploy.yml が実際に行う操作から決める。
#
#   | deploy.yml の操作                                   | 必要な権限                      | 付与範囲                    |
#   |-----------------------------------------------------|---------------------------------|-----------------------------|
#   | docker push（Artifact Registry へ）                 | roles/artifactregistry.writer   | リポジトリ subma のみ       |
#   | gcloud run deploy（service の image 差し替え）      | roles/run.developer             | プロジェクト                |
#   | gcloud run jobs update / execute --wait             | roles/run.developer             | プロジェクト                |
#   | gcloud run services describe（URL 表示）            | roles/run.developer             | プロジェクト                |
#   | 実行 SA（subma-run）を指定した revision / job の作成 | roles/iam.serviceAccountUser    | subma-run SA のみ           |
#
# 付与しないもの（以前は付与していた）:
#   - roles/run.admin: run.developer との差は IAM ポリシー変更（setIamPolicy）。
#     CI が Cloud Run の invoker 設定を変える必要はなく、変えられると未認証公開ができてしまう。
#     invoker 等の IAM は Terraform（cloud_run.tf）だけが管理する。
#   - roles/cloudsql.admin: CI は Cloud SQL を操作しない。マイグレーション Job は
#     実行 SA（subma-run、cloudsql.client 付き）として DB に接続するので、デプロイ SA に DB 権限は不要。
#   - roles/secretmanager.admin: CI は Secret を読まない・書かない。Cloud Run が Secret を読むのは
#     実行 SA（subma-run）の権限。Secret の値は運用者が gcloud で投入する（secret_manager.tf 参照）。
#   - roles/storage.admin: CI は Cloud Storage を使わない（イメージは Artifact Registry に置く）。
#   - roles/run.invoker: jobs execute は run.developer に含まれる（run.jobs.run）ので別途不要。
#   - プロジェクト全体の roles/iam.serviceAccountUser / roles/artifactregistry.writer:
#     使う SA・リポジトリは 1 つずつなので、リソース単位の付与に絞った（下記）。

resource "google_project_iam_member" "deployer_run_developer" {
  project = var.project_id
  role    = "roles/run.developer"
  member  = "serviceAccount:${google_service_account.deployer.email}"
}

# Artifact Registry への push は subma リポジトリだけに許可する
resource "google_artifact_registry_repository_iam_member" "deployer_writer" {
  location   = google_artifact_registry_repository.subma.location
  repository = google_artifact_registry_repository.subma.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.deployer.email}"
}

# Cloud Run の service / job は実行 SA に subma-run を使う。その SA を指定して
# revision や job を更新するには、デプロイ SA が subma-run に対して actAs できる必要がある。
# subma-tasks や deployer 自身など、他の SA には actAs させない。
resource "google_service_account_iam_member" "deployer_acts_as_cloud_run" {
  service_account_id = google_service_account.cloud_run.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.deployer.email}"
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
