# プロバイダ設定 + 共通ローカル変数
#
# state backend は GCS。バケットは事前に手動で作成する必要あり（PR-C の Nami 作業）。
# 「Terraform で state バケット自体を作る」と循環依存になるため。
#
# [ai-assisted]

terraform {
  backend "gcs" {
    # bucket / prefix は terraform init -backend-config で渡す（環境ごとに切替可能にするため）
    # 例: terraform init \
    #       -backend-config="bucket=subma-tfstate" \
    #       -backend-config="prefix=prod"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# ---------- 共通ラベル ----------

locals {
  common_labels = {
    app         = var.app_name
    environment = var.environment
    managed_by  = "terraform"
  }

  # 命名規則: <app>-<resource>-<env>（必要に応じて）
  name_prefix = "${var.app_name}-${var.environment}"
}

# ---------- 必要 API の有効化 ----------
# `terraform apply` の最初の壁になりやすいので Terraform 内で有効化する。
# `disable_on_destroy = false` で destroy 時に API を無効化しないようにする（他のリソースが依存している可能性）。

resource "google_project_service" "required_apis" {
  for_each = toset([
    "run.googleapis.com",               # Cloud Run
    "sqladmin.googleapis.com",          # Cloud SQL
    "cloudtasks.googleapis.com",        # Cloud Tasks
    "secretmanager.googleapis.com",     # Secret Manager
    "iam.googleapis.com",               # IAM
    "iamcredentials.googleapis.com",    # Service Account 短期トークン発行
    "artifactregistry.googleapis.com",  # コンテナイメージ Repo
    "cloudbuild.googleapis.com",        # （将来的にビルド時に使う場合）
    "firestore.googleapis.com",         # Firestore（v2 用、PR-B では定義のみ）
    "cloudscheduler.googleapis.com",    # Cloud Scheduler（v2 用、PR-B では定義のみ）
    "storage.googleapis.com",           # Cloud Storage
    "compute.googleapis.com",           # ネットワーク／VPC（Cloud SQL connector 用）
    "servicenetworking.googleapis.com", # Cloud SQL private IP（必要に応じて）
    "logging.googleapis.com",           # Cloud Logging
    "monitoring.googleapis.com",        # Cloud Monitoring
    "sts.googleapis.com",               # Workload Identity Federation
  ])

  service            = each.value
  disable_on_destroy = false
}

# ---------- Artifact Registry（コンテナイメージ置き場） ----------
# PR-C でビルド済みイメージをここに push する。

resource "google_artifact_registry_repository" "subma" {
  location      = var.region
  repository_id = var.app_name
  description   = "SubMa container images"
  format        = "DOCKER"
  labels        = local.common_labels

  depends_on = [google_project_service.required_apis]
}
