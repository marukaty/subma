# Development Log

Claude Code セッション間の引き継ぎログ。新しいエントリは**先頭**に追加する（最新が上）。
各 Phase の技術的な記録を要約して残す。

---

## 2026-05-22 (Phase 4-C: 実 GCP デプロイ)

**完了**:
- **事前準備**: Billing 設定・プロジェクト紐付け、必要 API 18 種有効化（run / sqladmin / cloudtasks / secretmanager / iam / artifactregistry / firestore 等）、予算アラート（50% / 80% / 95%）、Terraform state bucket 作成（versioning 有効）
- **Terraform 初回 apply**: `terraform.tfvars`（Git 管理外）作成 → GCS backend で init → **56 リソース新規作成**（Cloud SQL / Cloud Run / Cloud Run Job / Cloud Storage / Secret Manager × 4 / Service Account × 3 / WIF Pool + Provider / Cloud Tasks / Cloud Scheduler / Firestore / Artifact Registry / IAM bindings 等）。GitHub Variables 登録（`GCP_PROJECT_ID` / `GCP_WIF_PROVIDER` / `GCP_DEPLOYER_SA`）
- **アプリデプロイ**: `.github/workflows/deploy.yml`（OIDC + WIF + build → push → deploy → migrate Job）、`cloud_run_jobs.tf`（DB マイグレ用 Cloud Run Job）、Dockerfile を Cloud Run 向けに調整（Thruster → 素 Puma）。初回デプロイまでの修正:
  1. `PORT` env 予約名エラー → Terraform から削除
  2. `database.yml` の YAML 構文エラー（コロン含むソケットパス）→ 引用符化
  3. パスワードに YAML 特殊文字含むエラー → password も引用符化
  4. mysql2 が TCP 接続を試行 → socket 使用時は host を空文字に
  5. Puma が PORT 3000 で listen / Thruster 不調 → Thruster 除去
- `/up` health check → HTTP 200、`/` → 301 redirect to `/dashboard`
- Firebase 認可ドメインに Cloud Run URL を追加（手動設定）
- meta tag の `firebase-api-key` / `firebase-app-id` 空白問題 → cloud_run.tf を `FIREBASE_API_KEY` / `FIREBASE_APP_ID` env 名に修正
- 実 Google ログイン疎通確認 OK
- `docs/infrastructure-notes.md` 作成（Mermaid 全体構成図 / 技術選定理由 / コスト試算 / 運用手順）

**完了基準**: ✅ 本番環境でアプリ稼働 / ✅ `terraform apply` で再構築可能 / ✅ GitHub Actions 経由で main → 自動デプロイ / ✅ Google ログイン疎通

**次回**: Phase 5（観測性）: CI 完成 / SLO 設定 / k6 / README 再構成 / デモ動画。引落リマインドの実通知テスト

**コスト管理**: 月額目安 ~$10〜13（Cloud SQL db-f1-micro が支配的）。無料クレジット適用・予算アラート設定済み。クレジット終了前に `terraform destroy` で一時停止する方針（infrastructure-notes D-2）

**ハマったポイント**:
- Cloud Run の `PORT` env は予約名で明示禁止
- `database.yml` の env 展開はコロン含む値 / YAML 特殊文字含むパスワード両方で引用符必須
- mysql2 は host と socket 同時設定時、host を優先して TCP 接続を試みる
- Rails 8 Dockerfile の Thruster は Cloud Run と相性悪い（PORT 引き継ぎ問題）

**使用モデル**: Opus 4.7

---

## 2026-04-27 (Phase 1: セキュリティ基盤 & Firebase Auth)

**完了**:
- Firebase Auth（Google SSO）: `FirebaseAuthVerifier` 自前 JWT 検証（RS256, iss/aud/exp/iat/sub, 公開証明書 1h キャッシュ）、`User` モデル、`AuthController`（sign_in / sign_out）、簡易ログイン UI + 空ダッシュボード。Firebase Web SDK は gstatic CDN から Importmap 経由で読み込み（JSPM 経由は壊れる）。実 Google アカウントでログイン確認
- セキュリティ基盤: rack-attack（/auth/sign_in 5/min, /csv_imports 10/5min, 全般 60/10s）、secure_headers（CSP / HSTS / X-Frame-Options 等）、lograge（JSON 構造化ログ、user_id / request_id 付与）、brakeman / bundler-audit（0 warnings, 0 vulnerabilities）、GitHub Actions CI（scan_ruby + lint + test）
- AuditLog: `audit_logs` テーブル、`ApplicationController#record_audit_log`（GET 以外を自動記録）、`auth.sign_in / sign_in_failed / sign_out` を明示記録、RSpec で検証
- ドキュメント: SECURITY.md（脅威モデル T-01〜T-09）、AI_USAGE_GUIDELINE.md（CSV PII マスキング規則、AI 生成コード管理）、ADR-0001
- RSpec: 32 examples, 0 failures

**使用モデル**: Sonnet

**メモ**:
- Importmap で Firebase を vendor 取り込みすると動的 chunk 読込で 404 → gstatic CDN 直参照で解決
- Rails 8 のデフォルト `config.hosts` は test でも有効 → test.rb に `config.hosts << "www.example.com"` 追加
- docker compose で `RAILS_ENV=development` が rspec に伝搬する → rails_helper.rb で強制上書き
- `allow_browser :modern` は test ではスキップ

---

## 2026-04-27 (Phase 0: プロジェクト初期化)

**完了**:
- Rails 8.1.3 / Ruby 3.4.5 で `rails new subma`（`--database=mysql --css=tailwind --skip-javascript --skip-solid -T --skip-bootsnap`）
  - JavaScript は後続 Phase で手動導入（Rails 8 は importmap/esbuild/bun のみネイティブサポート）
  - Solid Queue/Cache/Cable はスキップし、Sidekiq + Redis を Phase 3 で導入
- RSpec / Capybara / Selenium 導入
- Docker 開発環境（Dockerfile.dev / docker-compose.yml: Rails + MySQL 8 + Redis 7、`http://localhost:3010` で HTTP 200 確認）
- 基本ドキュメント雛形（README, SECURITY, AI_USAGE_GUIDELINE, CLAUDE.md, ADR テンプレ）、Issue / PR テンプレ
- GitHub Private リポジトリ作成 + 初回 push

**メモ**:
- 設計書では Ruby 3.3.x / Rails 7 指定だったが、Ruby 3.4.5 / Rails 8.1.3 を採用（現行の安定版、Solid 系の選択肢、長期メンテナンス性）
- GitHub 無料プランの Private リポではブランチ保護ルールを設定できないため、運用規律で担保（CLAUDE.md に明記）
- 決済関連データを扱うため、リポジトリは Private
