# セキュリティ方針

SubMa は個人のクレジットカード明細 CSV を扱う性質上、PII（Personally Identifiable Information / 個人を特定できる情報）保護を最優先に設計する。

## 脅威モデル

### Primary（高リスク）
| ID | 脅威 | 影響 | 対策 |
|---|---|---|---|
| T-01 | CSV ファイル経由の PII 漏洩 | クレカ番号末尾・口座情報の漏洩 | NFR-S-09（取り込み完了時にファイルを削除、バケットのライフサイクル 1 日）、Cloud Storage の既定の暗号化、バケットの公開アクセス防止 |
| T-02 | Claude API 経由の PII 流出 | 個人取引データが Anthropic 側ログに残る | NFR-S-10 (`AiClassifier#mask_pii` で識別子・カード番号末尾を `XXXX` 化) |
| T-03 | Firebase JWT 偽造 | 他人のアカウントに成りすまし | RS256 公開証明書での厳格な署名検証、iss/aud/exp/iat/sub の全項目検証 |
| T-04 | セッションハイジャック | アカウント乗っ取り | Cookie HttpOnly + Secure + SameSite=Lax、HSTS、reset_session on sign_in |
| T-05 | Secret Manager に入れるべき情報のリポジトリコミット | 漏洩 → サービス停止 | `.env`・tfvars・tfstate を `.gitignore`、本番は Secret Manager（値は gcloud で投入し、Terraform の変数・state に入れない） |

### Secondary（中リスク）
| ID | 脅威 | 影響 | 対策 |
|---|---|---|---|
| T-06 | OWASP Top 10 一般（XSS / CSRF / SQLi 等） | 多様 | Rails 標準保護 + secure_headers + Brakeman CI |
| T-07 | レート制限なしの認証エンドポイントへのブルートフォース・過剰なリクエスト | アカウント探索・サービス停止 | Rack::Attack（`/auth/sign_in` 5 回/分、CSV 関連の POST 10 回/5 分、全体 60 回/10 秒）。利用者の IP は Rails の `request.remote_ip` と同じ規則で求め、Cloud Run の前段を経由した全員が 1 つの IP として数えられないようにする |
| T-08 | 公開鍵ローテーション後の検証失敗 | 一時的にログイン不可 | 公開証明書のキャッシュを最大 1 時間にとどめる（未知の kid は拒否） |
| T-09 | 監査証跡の欠損 | 攻撃検知・原因究明が困難 | 全書き込み操作で AuditLog 記録（NFR-S-05） |

### 公開運用で追加した脅威
| ID | 脅威 | 影響 | 対策 |
|---|---|---|---|
| T-10 | 不特定の第三者によるサインアップ・利用 | データ閲覧・API 利用料の消費 | ログイン許可リスト（招待制）。`email_verified`・`sign_in_provider == google.com`・許可メールの 3 条件、未設定・空なら全員拒否、毎リクエスト再判定（ADR-0006） |
| T-11 | Cloud Tasks のトークンの発行元の偽装（他の GCP プロジェクトの SA が発行した ID トークンで内部エンドポイントを呼ぶ） | 他人の取り込みの処理を勝手に起動される | `OidcVerifier` で署名・iss・aud に加えて `email_verified == true` と `email == CLOUD_TASKS_SA_EMAIL` を確認。設定が無ければ 500 で拒否、本番では検証を無効にできない |
| T-12 | AI 呼び出しのコスト攻撃（大きな CSV の繰り返し取り込み） | Claude API の利用料の増大 | CSV の行数上限（1,000 行）と、AI に送る行数の上限（取り込み 1 回・1 ユーザー 1 日・全体 1 日）。同じ店名・金額はまとめて 1 回だけ送る。外側の安全網として Anthropic コンソールの月額上限と GCP の予算アラート（ADR-0004「利用量の上限」） |

### スコープ外（v2 以降）
- 物理セキュリティ（GCP のデータセンター対策に依拠）
- DDoS 大規模対策（Cloud Armor / WAF は v2）

## 対策一覧（実装ステータス）

| 要件 ID | 内容 | ステータス | 実装場所 |
|---|---|---|---|
| NFR-S-01 | OWASP Top 10 対策 | 部分実装（CSP の厳格化は未対応） | Rails 標準 + secure_headers + Brakeman |
| NFR-S-02 | Brakeman / bundler-audit を CI 実行 | ✅ | `.github/workflows/ci.yml` |
| NFR-S-03 | Rack::Attack でレート制限 | ✅ | `config/initializers/rack_attack.rb` |
| NFR-S-04 | CSP / HSTS / X-Frame-Options | ✅（CSP は外部 CDN と `unsafe_eval` を許可しており、厳格化は未対応） | `config/initializers/secure_headers.rb`、`config/initializers/content_security_policy.rb` |
| NFR-S-05 | 監査ログを全書き込み操作で記録 | ✅ | `ApplicationController#record_audit_log` + `AuditLog` モデル |
| NFR-S-06 | Firestore セキュリティルール | 対象外（アプリから Firestore を使っていない） | - |
| NFR-S-07 | Secret Manager で API/DB 認証情報管理 | ✅ | `infra/terraform/secret_manager.tf`（器と accessor のみ Terraform、値は gcloud で投入）|
| NFR-S-08 | AI_USAGE_GUIDELINE.md | ✅ | `AI_USAGE_GUIDELINE.md` |
| NFR-S-09 | CSV ファイルは処理後に削除 | ✅（取り込み完了時に削除。失敗時は再処理のために残し、バケットのライフサイクル 1 日で削除。ADR-0005・ADR-0007） | `ProcessCsvJob`、`infra/terraform/cloud_storage.tf` |
| NFR-S-10 | Claude API 送信時に識別子除外・PII マスク | ✅ | `Classifiers::AiClassifier.mask_pii` |

## 認証・セッション

- **認証方式**: Firebase Auth（Google SSO）+ 自前 JWT 検証
  - 詳細: [docs/adr/0001-firebase-auth-strategy.md](./docs/adr/0001-firebase-auth-strategy.md)
- **セッション**: Rails Cookie（HttpOnly, Secure on production, SameSite=Lax, 最終アクセスから 12 時間で失効）
  - 設定: `config/initializers/session_store.rb`
  - 本番は `config.force_ssl` / `config.assume_ssl` を有効化（HTTPS へのリダイレクト、HSTS、Secure Cookie）
- **Host ヘッダ検証**: 本番は環境変数 `APP_HOST`（カンマ区切り）にあるホスト名だけを受け付ける（`/up` は除外）
  - `APP_HOST` が未設定・空のときは起動時に例外で停止する（設定漏れのまま検証なしで動かさない）
  - `APP_HOST=*` は検証の明示的な無効化。HTTP を受けない用途（イメージ作成時の `assets:precompile`、マイグレーション用 Cloud Run Job）だけで使い、起動時に警告ログを出す
- **サインイン時**: `reset_session` でセッション固定化攻撃を防止
- **許可リスト（招待制）**: `LoginAllowlist` が User 作成前に判定。許可メールは環境変数 `ALLOWED_LOGIN_EMAILS`（本番は Secret Manager）。毎リクエスト再判定し、外れたユーザーのセッションを破棄
  - 詳細: [docs/adr/0006-login-allowlist.md](./docs/adr/0006-login-allowlist.md)
- **JWT 検証**: RS256 / iss / aud / exp / iat / sub の全項目を検証

## CSV 取扱い

1. アップロード時: 入力を検証してから、Active Storage で Cloud Storage の一時保管バケットに保存する（GCS の既定の暗号化、公開アクセス防止、1 日で削除するライフサイクル）
2. 処理: 本番は Cloud Tasks から内部エンドポイントを呼び出して実行する（開発・テストは Sidekiq）。Tier 1/2/3 で分類する
3. **取り込みが完了したら元の CSV を削除する**（NFR-S-09）。失敗した取り込みは再処理のためにファイルを残し、バケットのライフサイクル（1 日）で消える（ADR-0007）
4. `transactions` テーブルには利用店名・金額・日付と分類結果を保存する。CSV のその他の列は保存しない
   - 利用店名は保存時・表示時にマスクしていない（マスクするのは AI に送るときだけ）。保存時のマスク・暗号化は未実装で、ADR-0005 のフォローアップとしている

### アップロード時の入力検証

保存（Active Storage への attach）とジョブ投入の前に `CsvUploadForm`（`app/forms/csv_upload_form.rb`）で検証し、問題があれば 422 で入力画面を再表示する（500 にしない）。

- パラメータは `params.expect(csv_import: [:file, :format])` で受け取り、それ以外のキーは無視する
- ファイル必須。拡張子は `.csv` のみ、Content-Type は `text/csv` / `text/plain` / `application/vnd.ms-excel` のみ
- サイズ上限は 1MB（環境変数 `CSV_MAX_UPLOAD_BYTES` でバイト数を指定可。未設定・不正値なら 1,048,576）。空ファイルは拒否
- 中身の確認: 先頭 16KB を読み、NUL バイトを含むもの・マジックナンバーで画像や ZIP 等と判定されるものは拒否。UTF-8（BOM 付き可）または Windows-31J として読めること、先頭 5 行が CSV として解釈できることを確認
- 行数の上限は 1,000 行（環境変数 `CSV_MAX_ROWS`）
- format は `CsvImport.formats` と `Csv::Parser::ADAPTERS` の両方にある値（実装済みのアダプタ）のみ
- 保存するファイル名はパス部分を除き、拡張子を残して 100 文字に切る

## AI への送信ルール

- 詳細: [AI_USAGE_GUIDELINE.md](./AI_USAGE_GUIDELINE.md)
- 要点:
  - 本物のユーザー CSV を Claude / Claude Code に渡さない
  - 本番アプリで Claude API に送る取引データは `mask_pii` でカード番号末尾等を `XXXX` 化
  - ユーザー識別子（user_id, firebase_uid, email）はプロンプトに含めない
  - AI の応答は提案として扱い、利用者が確認画面で確認してから登録する。分類（サブスクかどうかの区分）はコード側で決める
  - AI に送る行数には上限がある（T-12、ADR-0004「利用量の上限」）

## 監査ログ

- `AuditLog` モデルに以下を記録:
  - 認証イベント: `auth.sign_in` / `auth.sign_in_failed` / `auth.sign_out` / `auth.sign_in_denied`（許可リストで拒否。user は null、メールは保存しない） / `auth.session_revoked`（ログイン中に許可リストから外れた）
  - 退会: `account.delete_requested` / `account.deleted`（退会後も user_id を null にして残す）
  - 全書き込み操作: `<controller>.<action>` 形式（例: `subscriptions.create`）
  - 関連: user_id（認証前は null）/ resource_type / resource_id / ip_address / user_agent / created_at
- 保存期間: 90 日を目安とする。期限を過ぎた行を自動で削除する仕組みは未実装

## インフラの秘密値と権限

- **秘密値は tfstate に入れない**: Terraform は Secret Manager の Secret の器と、Cloud Run 実行 SA（`subma-run`）の accessor 権限だけを管理する。API キー・Rails master key・許可メールは Terraform の変数・tfvars に持たず、運用者が `gcloud secrets versions add` で投入する（手順: [docs/infrastructure-notes.md](./docs/infrastructure-notes.md) 8.9）
  - Terraform が版を管理しないので、漏洩時やローテーション時に手動で無効化した版が `terraform apply` で有効に戻ることはない
  - 例外: Cloud SQL のアプリ用パスワードは Terraform が `random_password` で生成し、DB ユーザーと Secret の両方に設定する（値の出どころが Terraform 自身のため）。tfstate の GCS バケットは閲覧権限を絞って扱う
- **デプロイ SA は最小権限**: GitHub Actions（WIF 経由）が使う `subma-deployer` は、`deploy.yml` の操作に必要な権限だけを持つ
  - `roles/run.developer`（service / job の更新と実行）、`roles/artifactregistry.writer`（リポジトリ `subma` のみ）、`roles/iam.serviceAccountUser`（実行 SA `subma-run` のみ）
  - Cloud SQL・Secret Manager・Cloud Storage の権限と、Cloud Run の IAM ポリシー変更権限（`run.admin`）は持たない。CI の認証情報が悪用されても、DB・秘密値・バケットには直接は届かない
  - ただし、デプロイ権限があれば実行 SA `subma-run` として任意のコードを動かせるため、間接的には到達しうる。デプロイ SA のロールを `run.developer` に限定し、WIF の条件でこのリポジトリの workflow からしか引き受けられないようにして緩和している
  - 対応表: [docs/infrastructure-notes.md](./docs/infrastructure-notes.md) 3.4

## 脆弱性報告

- 連絡先: web.namiya@gmail.com
- GitHub Issues での **公開報告は避ける**（リポジトリは Private だが、念のため）
- 受領後 7 日以内に応答を目標

## 参照

- ADR-0001 Firebase Auth Strategy
- ADR-0004 サブスク抽出の階層化分類器（利用量の上限）
- ADR-0005 CSV 取り込みにおける PII 保護戦略
- ADR-0006 ログイン許可リスト
- ADR-0007 CSV 取り込みジョブの冪等性と再実行
- AI_USAGE_GUIDELINE.md
