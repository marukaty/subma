# セキュリティ方針

SubMa は個人のクレジットカード明細 CSV を扱う性質上、PII（Personally Identifiable Information / 個人を特定できる情報）保護を最優先に設計する。

## 脅威モデル

### Primary（高リスク）
| ID | 脅威 | 影響 | 対策 |
|---|---|---|---|
| T-01 | CSV ファイル経由の PII 漏洩 | クレカ番号末尾・口座情報の漏洩 | NFR-S-09 (CSV 即削除), Cloud Storage 暗号化, アクセスログ |
| T-02 | Claude API 経由の PII 流出 | 個人取引データが Anthropic 側ログに残る | NFR-S-10 (`AiClassifier#mask_pii` で識別子・カード番号末尾を `XXXX` 化) |
| T-03 | Firebase JWT 偽造 | 他人のアカウントに成りすまし | RS256 公開証明書での厳格な署名検証、iss/aud/exp/iat/sub の全項目検証 |
| T-04 | セッションハイジャック | アカウント乗っ取り | Cookie HttpOnly + Secure + SameSite=Lax、HSTS、reset_session on sign_in |
| T-10 | 不特定の第三者によるサインアップ・利用 | データ閲覧・API 利用料の消費 | ログイン許可リスト（招待制）。`email_verified`・`sign_in_provider == google.com`・許可メールの 3 条件、未設定・空なら全員拒否、毎リクエスト再判定（ADR-0006） |
| T-05 | Secret Manager に入れるべき情報のリポジトリコミット | 漏洩 → サービス停止 | `.env` を `.gitignore`、本番は Secret Manager、CI で git-secrets 系チェック検討 |

### Secondary（中リスク）
| ID | 脅威 | 影響 | 対策 |
|---|---|---|---|
| T-06 | OWASP Top 10 一般（XSS / CSRF / SQLi 等） | 多様 | Rails 標準保護 + secure_headers + Brakeman CI |
| T-07 | レート制限なしの認証エンドポイントへのブルートフォース | アカウント探索 | Rack::Attack（5 req/min for /auth/sign_in） |
| T-08 | 公開鍵ローテーション後の検証失敗 | 一時的にログイン不可 | 公開証明書を 1 時間キャッシュ、署名検証エラー時のみキャッシュ無効化検討（Phase 5） |
| T-09 | 監査証跡の欠損 | 攻撃検知・原因究明が困難 | 全書き込み操作で AuditLog 記録（NFR-S-05） |

### スコープ外（v2 以降）
- 物理セキュリティ（GCP のデータセンター対策に依拠）
- DDoS 大規模対策（Cloud Armor / WAF は v2）

## 対策一覧（実装ステータス）

| 要件 ID | 内容 | ステータス | 実装場所 |
|---|---|---|---|
| NFR-S-01 | OWASP Top 10 対策 | 部分実装 | Rails 標準 + secure_headers / 詳細は Phase 5 まで継続 |
| NFR-S-02 | Brakeman / bundler-audit を CI 実行 | ✅ | `.github/workflows/ci.yml` |
| NFR-S-03 | Rack::Attack でレート制限 | ✅ | `config/initializers/rack_attack.rb` |
| NFR-S-04 | secure_headers で CSP / HSTS / X-Frame-Options | ✅（CSP は Phase 1 緩め、Phase 5 厳密化） | `config/initializers/secure_headers.rb` |
| NFR-S-05 | 監査ログを全書き込み操作で記録 | ✅ | `ApplicationController#record_audit_log` + `AuditLog` モデル |
| NFR-S-06 | Firestore セキュリティルール | 未（Phase 3） | `firestore.rules` |
| NFR-S-07 | Secret Manager で API/DB 認証情報管理 | 未（Phase 4 本番化時） | Cloud Run env vars + Secret Manager |
| NFR-S-08 | AI_USAGE_GUIDELINE.md | ✅ | `AI_USAGE_GUIDELINE.md` |
| NFR-S-09 | CSV ファイルは処理後即削除 | 未（Phase 3） | `ProcessCsvJob` 実装時 |
| NFR-S-10 | Claude API 送信時に識別子除外・PII マスク | 未（Phase 3） | `AiClassifier#mask_pii` |

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

## CSV 取扱い（Phase 3 で実装）

1. アップロード時: Cloud Storage に暗号化保存（GCS デフォルト）
2. 処理: Sidekiq 非同期 + Tier 1/2/3 で分類
3. **完了後: Cloud Storage の元 CSV を即削除**（NFR-S-09）
4. transactions テーブルには「分類結果」のみ残す（PII 最小化）

## AI への送信ルール

- 詳細: [AI_USAGE_GUIDELINE.md](./AI_USAGE_GUIDELINE.md)
- 要点:
  - 本物のユーザー CSV を Claude / Claude Code に渡さない
  - 本番アプリで Claude API に送る取引データは `mask_pii` でカード番号末尾等を `XXXX` 化
  - ユーザー識別子（user_id, firebase_uid, email）はプロンプトに含めない

## 監査ログ

- `AuditLog` モデルに以下を記録:
  - 認証イベント: `auth.sign_in` / `auth.sign_in_failed` / `auth.sign_out` / `auth.sign_in_denied`（許可リストで拒否。user は null、メールは保存しない） / `auth.session_revoked`（ログイン中に許可リストから外れた）
  - 全書き込み操作: `<controller>.<action>` 形式（例: `subscriptions.create`）
  - 関連: user_id（認証前は null）/ resource_type / resource_id / ip_address / user_agent / created_at
- 保存期間: 90 日（Phase 4 で TTL ジョブ実装予定）

## 脆弱性報告

- 連絡先: web.namiya@gmail.com
- GitHub Issues での **公開報告は避ける**（リポジトリは Private だが、念のため）
- 受領後 7 日以内に応答を目標

## 参照

- 要件定義書 §6.1 セキュリティ要件
- ADR-0001 Firebase Auth Strategy
- ADR-0006 ログイン許可リスト
- AI_USAGE_GUIDELINE.md
