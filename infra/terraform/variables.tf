# 入力変数定義
#
# 値は terraform.tfvars または環境変数（TF_VAR_xxx）で渡す。
# 機密値（DB パスワード等）は本ファイルや tfvars に直書きせず、
# Terraform が random_password で自動生成 → Secret Manager に格納する設計。
#
# [ai-assisted]

# ---------- 必須入力 ----------

variable "project_id" {
  description = "GCP プロジェクト ID（例: subma-prod）"
  type        = string
}

variable "github_repository" {
  description = "GitHub リポジトリ（OWNER/REPO 形式、例: marukaty/subma）。Workload Identity Federation の制約に使う。"
  type        = string
}

# ---------- アプリ秘密値（Secret Manager に格納） ----------

variable "rails_master_key" {
  description = "Rails master.key の中身（config/master.key の値）"
  type        = string
  sensitive   = true
}

variable "anthropic_api_key" {
  description = "Anthropic Claude API キー"
  type        = string
  sensitive   = true
}

variable "firebase_project_id" {
  description = "Firebase プロジェクト ID（Auth の aud 検証用）"
  type        = string
}

variable "firebase_web_api_key" {
  description = "Firebase Web SDK の apiKey（クライアント側で公開可能だが、運用上は Secret 経由で配布）"
  type        = string
  sensitive   = true
}

variable "firebase_auth_domain" {
  description = "Firebase Auth domain（例: subma-xxx.firebaseapp.com）"
  type        = string
}

variable "firebase_app_id" {
  description = "Firebase Web App ID（例: 1:330247522102:web:xxx）。ブラウザ側公開値。"
  type        = string
}

# ---------- 既定値あり ----------

variable "region" {
  description = "GCP リージョン"
  type        = string
  default     = "asia-northeast1"
}

variable "zone" {
  description = "GCP ゾーン（Cloud SQL 等で使用）"
  type        = string
  default     = "asia-northeast1-a"
}

variable "environment" {
  description = "環境タグ（prod / staging 等）。リソース名のサフィックスや label に使う。"
  type        = string
  default     = "prod"
}

variable "app_name" {
  description = "アプリ名（リソース名のプレフィックス）"
  type        = string
  default     = "subma"
}

variable "container_image" {
  description = "Cloud Run にデプロイするコンテナイメージ。PR-C で実際のイメージタグに差し替える。"
  type        = string
  default     = "gcr.io/cloudrun/hello"
}

# ---------- Cloud SQL 設定 ----------

variable "cloud_sql_tier" {
  description = "Cloud SQL マシンタイプ（個人ポートフォリオ規模では db-f1-micro で十分）"
  type        = string
  default     = "db-f1-micro"
}

variable "cloud_sql_database_name" {
  description = "Cloud SQL 上のデータベース名"
  type        = string
  default     = "subma_production"
}

variable "cloud_sql_user_name" {
  description = "Cloud SQL のアプリ用ユーザー名"
  type        = string
  default     = "subma_app"
}
