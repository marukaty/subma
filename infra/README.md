# SubMa Infrastructure (Terraform)

SubMa の本番インフラ（Google Cloud の Cloud Run 単体構成）を Terraform で管理する。

## 構成

```
infra/terraform/
├── versions.tf          # Terraform / プロバイダのバージョン固定
├── variables.tf         # 入力変数（project_id、Firebase の公開値など。秘密値は持たない）
├── main.tf              # プロバイダ設定 + state backend + 必要 API 有効化 + Artifact Registry
├── iam.tf               # Service Account 3 つ + Workload Identity Federation
├── cloud_sql.tf         # MySQL 8.0 (db-f1-micro)
├── cloud_storage.tf     # CSV 一時保存バケット（1 日後自動削除）
├── secret_manager.tf    # Secret の器と accessor 権限（値は gcloud で投入）
├── cloud_tasks.tf       # process-csv キュー
├── cloud_run.tf         # subma-web サービス
├── cloud_run_jobs.tf    # DB マイグレーション用の Cloud Run Job
├── firestore.tf         # Firestore database（作成のみ。アプリからは未使用）
└── cloud_scheduler.tf   # リソースなし（コメントのみ）
```

## アーキテクチャ概要

```
[ User Browser ]
   ↓ HTTPS
[ Cloud Run (subma-web) ]  ← min-instances=0、cloud_run_sa
   ↓ unix socket
[ Cloud SQL db-f1-micro (MySQL) ]
[ Cloud Storage (CSV 一時、1 日で自動削除) ]
[ Secret Manager (RAILS_MASTER_KEY, ANTHROPIC_API_KEY, Firebase, DB password) ]

[ Cloud Tasks Queue (process-csv) ] → HTTP push (OIDC) → [ Cloud Run /internal/jobs/process_csv ]

[ GitHub Actions ] ─OIDC─→ [ Workload Identity Federation ] ─assume─→ [ deployer SA ]
```

**月額目安**: GCP 分は ~$10〜13（内訳は `docs/infrastructure-notes.md` 7.1）。Claude API は別請求で、アプリ側の上限により 1 日あたり数ドルまで

## 初回セットアップ手順（手動作業）

本番に初めて適用する流れ。`<PROJECT_ID>` は使う GCP プロジェクトの ID に置き換える。

### 0. 前提

- Google Cloud アカウントあり、課金有効化済み
- ローカルに `terraform` コマンドあり（>=1.10）
- ローカルに `gcloud` コマンドあり、`gcloud auth application-default login` 済み

### 1. GCP プロジェクト作成と最低限の API 有効化

```bash
# プロジェクト作成（ID は変更可、以下例）
gcloud projects create <PROJECT_ID> --name="SubMa Production"
gcloud config set project <PROJECT_ID>

# 課金アカウントを紐付け（GCP コンソールで実施するのが楽）

# Terraform が初回 apply で他の API を有効化するため、最低限 IAM と Cloud Resource Manager だけ先に
gcloud services enable iam.googleapis.com cloudresourcemanager.googleapis.com
```

### 2. Terraform state 用 GCS バケット作成（手動）

state バケット自体を Terraform で作ると循環依存になるため、初回のみ手動。

```bash
gcloud storage buckets create gs://subma-tfstate \
  --location=asia-northeast1 \
  --uniform-bucket-level-access

# バージョニング有効化（state 履歴保持）
gcloud storage buckets update gs://subma-tfstate --versioning
```

### 3. デプロイ用 SA を一時的に手動作成

初回 `terraform apply` 用の SA。Terraform が自分自身（`deployer` SA）を作る前に必要。

```bash
gcloud iam service-accounts create subma-bootstrap \
  --display-name="SubMa initial bootstrap"

# プロジェクトオーナー権限を一時付与（apply 後に削除）
gcloud projects add-iam-policy-binding <PROJECT_ID> \
  --member="serviceAccount:subma-bootstrap@<PROJECT_ID>.iam.gserviceaccount.com" \
  --role="roles/owner"

# 認証ファイル取得（初回 apply 後に削除推奨）
gcloud iam service-accounts keys create ~/.subma-bootstrap.json \
  --iam-account=subma-bootstrap@<PROJECT_ID>.iam.gserviceaccount.com

export GOOGLE_APPLICATION_CREDENTIALS=~/.subma-bootstrap.json
```

### 4. terraform.tfvars 作成

```bash
cd infra/terraform
cat > terraform.tfvars <<'EOF'
project_id             = "<PROJECT_ID>"
github_repository      = "OWNER/subma"
firebase_project_id    = "<FIREBASE_PROJECT_ID>"
firebase_auth_domain   = "<FIREBASE_PROJECT_ID>.firebaseapp.com"
firebase_app_id        = "<FIREBASE_APP_ID>"
# 初回は仮の URL を入れ、手順 7 で確定した URL に置き換える
cloud_tasks_target_url = "https://example.invalid/internal/jobs/process_csv"
EOF

# tfvars はリポジトリにコミットしない（.gitignore 済み）
# API キー・master key などの秘密値は tfvars に書かない。
# Secret の器だけ Terraform で作り、値は gcloud で投入する（次の手順 5）
```

### 5. terraform init / plan / apply

```bash
terraform init \
  -backend-config="bucket=subma-tfstate" \
  -backend-config="prefix=prod"

# 5-1. Secret の器と accessor 権限だけ先に作る
terraform apply \
  -target=google_secret_manager_secret.subma \
  -target=google_secret_manager_secret_iam_member.cloud_run_accessor \
  -target=google_secret_manager_secret_version.cloud_sql_app_password \
  -target=google_secret_manager_secret.allowed_login_emails \
  -target=google_secret_manager_secret_iam_member.allowed_login_emails_accessor

# 5-2. 秘密値を投入（手順: docs/infrastructure-notes.md 8.9。許可メールは 8.5）
#      rails-master-key / anthropic-api-key / firebase-web-api-key / allowed-login-emails

# 5-3. 残りを作る
terraform plan -out=plan.out
terraform apply plan.out
```

最初の apply は API 有効化のため数分〜10 分かかる。

### 6. 後始末

```bash
# bootstrap SA の鍵を削除（漏洩リスクを下げる）
rm ~/.subma-bootstrap.json
unset GOOGLE_APPLICATION_CREDENTIALS

# 以降は WIF 経由で GitHub Actions が deployer SA を assume してデプロイする（.github/workflows/deploy.yml）
```

### 7. CLOUD_TASKS_TARGET_URL の更新

`cloud_run.tf` の `CLOUD_TASKS_TARGET_URL` は `var.cloud_tasks_target_url`（terraform.tfvars で設定）から渡す。初回 apply 時はプレースホルダ URL を設定しておく。
初回 apply 後に Cloud Run の URL が確定するので:

```bash
# 確定した Cloud Run URL を確認
terraform output cloud_run_url
# 例: https://subma-web-xxxxxxxxxx-an.a.run.app

# 必要に応じて variable で上書きするか、手動で gcloud run services update で env を更新
gcloud run services update subma-web \
  --region=asia-northeast1 \
  --update-env-vars=CLOUD_TASKS_TARGET_URL=https://subma-web-xxxxxxxxxx-an.a.run.app/internal/jobs/process_csv
```

確定した URL は terraform.tfvars の `cloud_tasks_target_url` にも反映し、もう一度 `terraform apply` する（`APP_HOST` もこの URL のホスト部分から作られる）。

## 通常運用

- インフラ変更は PR で行う
- PR では GitHub Actions（`.github/workflows/terraform.yml`）が `terraform fmt -check` と `terraform validate` を実行する
- `terraform plan` / `apply` は運用者が手元で実行する（CI は GCP のインフラ変更権限を持たない）

## 運用上の注意

- **Cloud SQL deletion_protection が有効**。インスタンス削除には先に `deletion_protection = false` に変更して apply してから削除すること
- **Secret Manager の Secret 値変更**: Terraform では行わない。`gcloud secrets versions add` で新しい版を追加し、Cloud Run の新しいリビジョンを作って反映する（`docs/infrastructure-notes.md` 8.9）
- **state バケットの versioning** が有効なので、誤って削除しても復元可能

## 参考

- ADR-0003 CSV 処理パイプライン（追記: 本番は Cloud Tasks）
- `docs/infrastructure-notes.md`（構成・権限・運用手順）
