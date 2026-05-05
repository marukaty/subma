# SubMa Infrastructure (Terraform)

SubMa の本番インフラ（GCP D-1 構成）を Terraform で管理する。

## 構成

```
infra/terraform/
├── versions.tf          # Terraform / プロバイダのバージョン固定
├── variables.tf         # 入力変数（project_id、秘密値など）
├── main.tf              # プロバイダ設定 + state backend + 必要 API 有効化 + Artifact Registry
├── iam.tf               # Service Account 3 つ + Workload Identity Federation
├── cloud_sql.tf         # MySQL 8.0 (db-f1-micro)
├── cloud_storage.tf     # CSV 一時保存バケット（1 日後自動削除）
├── secret_manager.tf    # 秘密値（RAILS_MASTER_KEY 等）
├── cloud_tasks.tf       # process-csv キュー
├── cloud_run.tf         # subma-web サービス
├── firestore.tf         # Firestore database（v2 用、定義のみ）
└── cloud_scheduler.tf   # 引落リマインド（v2 用、コメントスケッチ）
```

## アーキテクチャ概要（D-1 構成）

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

**月額目安**: $8〜17（Cloud SQL $7-10 + Cloud Run $0-3 + Anthropic $1-5）

## 初回セットアップ手順（手動作業）

PR-B のコードがマージされた後、本番に初めて適用する流れ。

### 0. 前提

- Google Cloud アカウントあり、課金有効化済み
- ローカルに `terraform` コマンドあり（>=1.10）
- ローカルに `gcloud` コマンドあり、`gcloud auth application-default login` 済み

### 1. GCP プロジェクト作成と最低限の API 有効化

```bash
# プロジェクト作成（ID は変更可、以下例）
gcloud projects create subma-prod --name="SubMa Production"
gcloud config set project subma-prod

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
gcloud projects add-iam-policy-binding subma-prod \
  --member="serviceAccount:subma-bootstrap@subma-prod.iam.gserviceaccount.com" \
  --role="roles/owner"

# 認証ファイル取得（初回 apply 後に削除推奨）
gcloud iam service-accounts keys create ~/.subma-bootstrap.json \
  --iam-account=subma-bootstrap@subma-prod.iam.gserviceaccount.com

export GOOGLE_APPLICATION_CREDENTIALS=~/.subma-bootstrap.json
```

### 4. terraform.tfvars 作成

```bash
cd infra/terraform
cat > terraform.tfvars <<'EOF'
project_id            = "subma-prod"
github_repository     = "OWNER/subma"
firebase_project_id   = "subma-xxxxx"
firebase_auth_domain  = "subma-xxxxx.firebaseapp.com"
firebase_web_api_key  = "AIzaSyXXX"
rails_master_key      = "XXXXXXXXXXXX"
anthropic_api_key     = "sk-ant-xxx"
EOF

# tfvars はリポジトリにコミットしない（.gitignore 済み）
```

### 5. terraform init / plan / apply

```bash
terraform init \
  -backend-config="bucket=subma-tfstate" \
  -backend-config="prefix=prod"

terraform plan -out=plan.out
terraform apply plan.out
```

最初の apply は API 有効化のため数分〜10 分かかる。

### 6. 後始末

```bash
# bootstrap SA の鍵を削除（漏洩リスクを下げる）
rm ~/.subma-bootstrap.json
unset GOOGLE_APPLICATION_CREDENTIALS

# 以降は WIF 経由で GitHub Actions が deployer SA を assume してデプロイする（PR-C で構築）
```

### 7. CLOUD_TASKS_TARGET_URL の更新

`cloud_run.tf` の `CLOUD_TASKS_TARGET_URL` は初回 apply 時にプレースホルダ URL になっている。
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

このループは PR-C で自動化する（Terraform を二段階 apply するか、デプロイスクリプトで上書きするか）。

## 通常運用（PR-C 完了後）

- インフラ変更は PR で行う
- PR 作成時に GitHub Actions が `terraform plan` を自動実行（コメント形式で結果を貼る）
- main ブランチへのマージで `terraform apply` が自動実行される

## 運用上の注意

- **Cloud SQL deletion_protection が有効**。インスタンス削除には先に `deletion_protection = false` に変更して apply してから削除すること
- **Secret Manager の Secret 値変更**: Terraform で `secret_data` を更新して apply すると新バージョンが作成される（古いバージョンは無効化）
- **state バケットの versioning** が有効なので、誤って削除しても復元可能

## 参考

- ADR-0003 CSV 処理パイプライン（Phase 4 追記: Cloud Tasks 採択）
- Issue #17 Phase 4 全体計画
