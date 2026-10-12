# Development Log

開発の経過を Phase ごとに要約した記録。新しいエントリは**先頭**に追加する（最新が上）。

## 担当の切り分け

- **構成の判断（作者）**: 本番を Cloud Run + Cloud SQL の最小構成とし、Memorystore を使わず本番のみ Cloud Tasks に置き換える判断（ADR-0003 Phase 4 追記、コスト根拠）をはじめ、各 ADR の決定は作者が行った。Terraform 定義の PR で確認事項として挙げた GCP プロジェクト ID・state バケット名・削除保護（Cloud SQL / Firestore）の扱いも作者が判断した
- **運用作業（作者が手元環境で実施）**: Phase 4-C での課金の有効化とプロジェクト紐付け、必要 API の有効化、予算アラート（50% / 80% / 95%）の設定、Terraform state バケットの手動作成、`terraform.tfvars`（Git 管理外）の作成と初回 `terraform apply`、GitHub Variables の登録、Firebase 認可ドメインへの Cloud Run URL の追加、実 Google アカウントでのログイン疎通確認
- **生成 AI の支援範囲**: Terraform 定義・デプロイ用ワークフロー・初回デプロイ時の修正を含むコードと本ログの記述は、生成 AI（Claude Code）の支援で作成した（Terraform 定義ファイルの冒頭コメントと、コミットメッセージの `Co-Authored-By` / `[ai-assisted]` 表記を参照）。作者が PR の内容を確認してマージし、インフラへの適用を行った

---

## 2026-10-10〜10-12 (公開運用に向けた堅牢化)

本番環境を招待制で外部に公開して運用するため、セキュリティ・信頼性・コストの面を見直した（#52〜#68）。

**完了**:
- **依存関係**: 脆弱性情報のある gem を更新（#54）
- **本番設定の強化**（#56）: Action Mailbox / Action Text / Action Cable を読み込まない、Active Storage のルートを無効化。`force_ssl` / `assume_ssl`、セッションを最終アクセスから 12 時間で失効、`APP_HOST` による Host ヘッダ検証（未設定なら起動時に停止）
- **ログイン許可リスト**（#55）: 10-09 のエントリを参照（ADR-0006）
- **内部エンドポイントの発行元確認**（#57）: Cloud Tasks の OIDC トークンで、iss・aud に加えて発行した SA のメールアドレスを確認。設定が無ければ 500 で拒否し、本番では検証を無効にできない
- **CSV アップロードの入力検証**（#58）: `params.expect` と Form Object `CsvUploadForm` で、拡張子・Content-Type・サイズ（1MB）・中身（NUL バイト・マジックナンバー・文字コード・先頭 5 行の解釈）を検証し、問題があれば 422
- **UTF-8 BOM 付き CSV の取り込み失敗を修正**（#62）
- **本番の Active Storage を Cloud Storage に**（#59）: アップロードを受けたインスタンスとジョブを実行するインスタンスが別でも読めるようにした。認証は実行 SA の ADC
- **CSV ジョブの冪等化**（#60、ADR-0007）: 行ロックと状態の確認で、同じタスクが複数回届いても処理は 1 回。1 ユーザーの同時処理は 1 件。Cloud Run の timeout と Cloud Tasks の dispatch_deadline を 900 秒にそろえた。失敗時はファイルを残し、画面の「再実行」と rake タスクで再処理できる
- **判定の改善**: 店名の NFKC 正規化と通信費の対象外化（#63、ADR-0008）。Tier 2 を「件数」から「取引日の間隔」（月額 25〜35 日、年額 360〜370 日）に変更（#64）
- **再取り込みの重複防止**（#65）: 他の取り込みで保存済みの同じ取引を判定前に除く。既存データの掃除用に `transactions:dedup` を追加。サブスク判定の件数を一覧と一致させた
- **退会と試用データ**（#66）: 設定画面からアカウントとすべてのデータを削除できる（`AccountDeletion`、1 トランザクション、ファイルはコミット後に削除）。サンプル CSV（`public/samples/sample_rakuten.csv`）を追加
- **AI 利用量の上限**（#68、ADR-0004「利用量の上限」）: CSV の行数（1,000 行）と、AI に送る行数（取り込み 1 回 300 行、1 ユーザー 1 日 500 行、全体 1 日 2,000 行）に上限。上限を超えた行は未判定として保存。同じ店名・金額の行はまとめて 1 回だけ送る
- **インフラの権限と秘密値**（#67）: デプロイ SA を `run.developer`・リポジトリ単位の `artifactregistry.writer`・実行 SA への `serviceAccountUser` に縮小。API キー・master key・許可リストの値を Terraform の変数と state から外し、`gcloud secrets versions add` で投入する方式に変更
- **ドキュメント**（#52、#53、#61）: インフラの判断と運用作業の担当を本ログに明記、全 ADR の決定者の表記を統一

**メモ**:
- Cloud Tasks は at-least-once 配信のため、受け側の処理は必ず冪等にする
- Cloud Run 上では複数インスタンスになりうるため、日次の上限などの数え方はメモリではなく DB（行ロック）で行う

---

## 2026-10-09 (公開運用に向けた堅牢化: ログイン許可リスト)

**完了**:
- `LoginAllowlist` サービス追加。通す条件は `email_verified == true`・`firebase.sign_in_provider == "google.com"`・許可メール（`ALLOWED_LOGIN_EMAILS`、大文字小文字と前後空白を無視）の 3 つすべて
- 未設定・空は全環境で全員拒否（fail-closed）。`*` は development / test でだけ全員許可、production では無視
- `AuthController#sign_in` で User 作成前に判定（拒否時 403 `not_allowed`、User を作らない）。`ApplicationController#current_user` で毎リクエスト再判定し、外れたらセッション破棄
- 監査ログ `auth.sign_in_denied` / `auth.session_revoked` 追加。ログのメールはマスク（先頭 2 文字 + ドメイン）
- Terraform: Secret `allowed-login-emails` の器と accessor 権限のみ作成、Cloud Run env に `secret_key_ref` で注入（値は gcloud で帯域外投入）
- `spec/support/sign_in_helper.rb` を current_user スタブから「verifier スタブ + 実 POST」に変更（締め出しをテストできるように）
- ADR-0006、`docs/infrastructure-notes.md` 8.5 / 8.6、SECURITY.md 更新

**未完了・次回引き継ぎ**:
- Secret への値投入と Firebase コンソール設定（手作業。infrastructure-notes 8.5 / 8.6）

**使用モデル**: Opus

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

**コスト管理**: 月額目安 ~$10〜13（Cloud SQL db-f1-micro が支配的）。無料クレジット適用・予算アラート設定済み。クレジット終了前に `terraform destroy` で一時停止する方針（手順は infrastructure-notes 8.3）

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
