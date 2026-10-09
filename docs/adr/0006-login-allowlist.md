# ADR-0006: ログインの許可リスト（招待制）

- **ステータス**: 採択
- **日付**: 2026-10-09
- **決定者**: なみ屋
- **関連 ADR**: ADR-0001（Firebase Auth Strategy）

## 背景（Context）

SubMa をインターネットに公開し、不特定の利用者がアクセスできる状態にするにあたり、アクセス制御を見直した。

公開前の実装には次の問題があった:

- `AuthController#sign_in` は ID トークンを検証した直後に `User.from_firebase_claims` で User を作るため、Google アカウントを持っていれば誰でもサインアップできる
- ID トークンの `email_verified` と `firebase.sign_in_provider` を確認していない。Firebase 側でメール/パスワード等のログイン方法が有効になっていると、未確認のメールアドレスで任意のアドレスを名乗れる
- セッションは `session[:user_id]` だけを見ており、特定ユーザーのアクセスを取り消す手段がない
- email を持たないトークン（匿名ログイン等）では `save!` が `RecordInvalid` を出し 500 になる

利用者が増えると、CSV 内の個人情報を預かる量と、Claude API の利用料が利用者数に比例して増える。公開の初期段階では、運用者が把握している少人数に利用を限定したい。

## 検討した選択肢（Options Considered）

### 選択肢 A: 環境変数（Secret Manager）の許可リスト + アプリ側で判定
- メリット: 追加の基盤が不要。実装が小さい（サービス 1 つと controller の数行）。Secret Manager のバージョンで変更履歴が残る
- デメリット: 追加・削除に gcloud 操作と新リビジョンの作成が必要。利用者が数十人を超えると管理しにくい

### 選択肢 B: Identity-Aware Proxy（IAP）
- メリット: アプリに手を入れずに Google アカウント単位でアクセスを絞れる
- デメリット: Cloud Run の前にロードバランサが必要で、固定費と構成が増える。Cloud Tasks からの内部 API 呼び出し（OIDC）と認証が二重になり、経路の設計が複雑になる

### 選択肢 C: DB で招待コード・招待テーブルを管理
- メリット: 管理画面から追加・削除でき、人数が増えても運用しやすい
- デメリット: 招待の発行・失効・管理画面の権限など、機能として大きい。現段階の利用者数に対して過剰

## 決定（Decision）

**選択肢 A** を採用する。少人数の利用者を運用で追加できれば十分で、追加の固定費と構成要素を増やさずに済むため。

### ログインを通す条件（3 つすべて）

1. ID トークンの `email_verified == true`（真偽値で厳密に比較）
2. ID トークンの `firebase.sign_in_provider == "google.com"`
3. メールアドレスが環境変数 `ALLOWED_LOGIN_EMAILS`（カンマ区切り）に含まれる。比較は前後の空白を除き、大文字小文字を区別しない

1 と 2 を確認するのは、Firebase コンソールで他のログイン方法が誤って有効になっても、未確認のメールアドレスで許可メールを名乗れないようにするため（コンソール設定との多層防御）。

### 空リストの扱い（fail-closed）

- `ALLOWED_LOGIN_EMAILS` が未設定・空・空白だけの場合は、**全環境で全員を拒否する**
- 全員を許可したい場合は `*` を明示的に設定する。`*` は development / test（`Rails.env.local?`）でだけ有効で、**production では無視する**
- development では `docker-compose.yml` が未指定時に `*` を渡す。test では spec の共通設定で example ごとに `*` を設定し、許可リストを確かめる example で上書きする

「本番だけ空=拒否、開発は空=許可」とすると、環境によって同じ設定の意味が変わり、設定漏れが本番で全員許可につながる経路を残す。空の意味を全環境で「拒否」にそろえ、全許可は明示的な値でしか表せないようにした。

### 判定のタイミング

- **ログイン時**: `AuthController#sign_in` で ID トークンを検証した直後、**User を作る前**に `LoginAllowlist.check(claims)` で判定する。拒否した人の User 行は作らない（個人情報を残さない）。既存ユーザーが拒否された場合も User を更新しない
- **毎リクエスト**: `ApplicationController#current_user` でセッションのユーザーを解決するたびに、`User.email` を許可リストで再判定する。外れていれば `reset_session` してログイン画面へ戻す（HTML はリダイレクト、JSON は 403）
  - 毎リクエストで確認できるのはメールアドレスだけ（ID トークンはセッションに保存しないため）。`email_verified` と `sign_in_provider` はログイン時に確認済み
  - 判定は環境変数を読むだけで、DB や外部 API を呼ばないので、毎リクエストでも負荷はほぼ増えない

### 拒否時の応答と記録

- `POST /auth/sign_in` は **403** `{ ok: false, error: "not_allowed", message: "このサービスは招待制です。…" }` を返す（既存の 401 `invalid_token` と区別する）。フロントは Firebase 側もサインアウトし、メッセージを表示する
- ログイン画面に「このサービスは招待制です」を常に表示する
- `Rails.logger.warn` に拒否理由（`email_not_verified` / `provider_not_allowed` / `email_not_listed`）と、マスクしたメールアドレス（先頭 2 文字 + ドメイン）を出す
- 監査ログに `auth.sign_in_denied`（user は null、メールアドレスは保存しない）と `auth.session_revoked`（締め出したユーザー）を記録する

### 値の管理（インフラ）

- 許可メールは個人情報のため、リポジトリ・Terraform の変数・tfvars・tfstate に入れない
- Terraform は Secret Manager の Secret `allowed-login-emails` の器と、Cloud Run SA の accessor 権限だけを作る。値は `gcloud secrets versions add` で帯域外に投入する
- Cloud Run は既存の Secret と同じく `value_source.secret_key_ref`（`version = "latest"`）で環境変数 `ALLOWED_LOGIN_EMAILS` に注入する
- 手順: `docs/infrastructure-notes.md` 8.5（運用）・8.6（Firebase コンソール）

## 結果（Consequences）

### ポジティブ
- 許可していない人は User 行も作られず、アプリの機能（CSV 取り込み・AI 判定）に到達できない
- 設定漏れ・設定ミスは「全員拒否」側に倒れる
- 許可を外せば、新リビジョンへの切り替え後、ログイン中のユーザーも次のリクエストで締め出される
- 匿名ログイン等の email を持たないトークンは 500 ではなく 403 になる

### ネガティブ・トレードオフ
- Cloud Run は Secret の `latest` をリビジョン起動時に解決するため、値を更新しただけでは反映されない。新しいリビジョンを作る運用が必要（手順に記載）
- 許可メールの追加・削除に gcloud の権限が必要で、利用者が自分で申請・登録する仕組みはない
- 許可リストのメールアドレスと Google アカウントのメールアドレスが一致することに依存する。Google 側でメールアドレスを変更した利用者は、リストの更新が必要

### フォローアップ作業
- Firebase コンソールでログイン方法を Google だけにし、承認済みドメインと Web API キーの制限を設定する（手作業 / `docs/infrastructure-notes.md` 8.6）
- 利用者が数十人を超える場合は、選択肢 C（DB 管理の招待）への移行を検討する
- 許可した利用者による過剰な利用は本 ADR の範囲外。利用量の上限は別途設ける

## 参考リンク

- Firebase: Verify ID tokens using a third-party JWT library
- Cloud Run: Configure secrets（環境変数として Secret を参照する場合の `latest` の解決タイミング）
