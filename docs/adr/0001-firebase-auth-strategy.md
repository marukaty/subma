# ADR-0001: Firebase Auth 統合方式と JWT 検証戦略

- **ステータス**: 採択
- **日付**: 2026-04-27
- **決定者**: なみ屋
- **関連 ADR**: なし

## 背景（Context）

SubMa はユーザー認証に Firebase Auth（Google SSO）を採用する（要件定義書 F-01）。

Rails 側で Firebase が発行した ID トークン（JWT）を受け取り、ユーザーを識別する必要がある。実装方式として 2 軸 × 2 択の選択肢がある:

1. **検証ライブラリ**: `firebase-auth-rails` gem を使う / 手書きで JWT 検証する
2. **セッション管理**: 各リクエストで JWT を毎回検証 / 初回検証後は Rails のセッション Cookie を使う

## 検討した選択肢（Options Considered）

### 選択肢 A: `firebase-auth-rails` gem + JWT 毎回検証
- メリット: 実装が短い、メンテ実績あり
- デメリット:
  - gem の最新 Rails 対応が遅れがち（実際 Rails 8 サポートはまだ限定的）
  - JWT 毎回検証は HTTP 越しに公開証明書を取得する必要があり、レイテンシ・障害点が増える（キャッシュは可能だが）
  - 内部の検証処理が gem に隠れ、トレードオフを把握・説明しにくい

### 選択肢 B: 手書き JWT 検証 + 初回検証後はセッション Cookie
- メリット:
  - 依存ライブラリが少ない（`jwt` gem のみ）。Rails 8 完全対応
  - JWT の検証ロジック（iss/aud/exp/iat/sig/sub）を明示的に実装するため**監査しやすく、セキュリティレビューで確認しやすい**
  - 一度検証したらセッション Cookie で済むため、リクエスト毎の Firebase 公開証明書取得が不要
  - Cookie の HttpOnly / Secure / SameSite を Rails 標準の仕組みで一括管理できる
- デメリット:
  - 公開証明書の取得・キャッシュ実装を自前で持つ
  - Firebase 側でユーザーが削除・無効化された場合の追従が遅れる（次回ログイン時まで気づかない）
    - これは MVP ではほぼ問題にならない（自分のみがユーザー）。将来 Firestore リアルタイムで失効通知を受ける案も可

### 選択肢 C: gem + 毎回 JWT 検証（gem の機能で session 不要）
- 検討するも、gem のメンテ状況とロックイン懸念で却下

## 決定（Decision）

**選択肢 B（手書き JWT 検証 + セッション Cookie）を採用する**。

実装:
- `app/services/firebase_auth_verifier.rb` で `jwt` gem を使い ID トークンを RS256 検証
- 公開証明書（`https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com`）を `Rails.cache` に最大 1 時間キャッシュ
- 検証項目: `iss`, `aud`, `exp`, `iat`, 署名, `sub` 非空
- `AuthController#sign_in` で初回検証 → `User.from_firebase_claims` で find_or_create → `session[:user_id]` 設定
- 以降のリクエストは `current_user` を `session[:user_id]` から復元
- ログアウト時は `reset_session` + フロント側で `firebase.signOut()`

## 結果（Consequences）

### ポジティブ
- Rails 8 へのアップデート時に gem 互換性を心配しなくて良い
- 検証ロジックが 1 ファイル（約 70 行）に閉じており、コード監査しやすい
- セッション Cookie 戦略により、Firebase の公開証明書取得をログイン時のみに限定できる（性能・障害耐性）

### ネガティブ・トレードオフ
- Firebase 側でのユーザー無効化が即時に Rails に反映されない
  - 対策案（必要になったら）: セッションに JWT 残り時間を保存、定期的に再検証する仕組みを追加
- 公開証明書のキャッシュ TTL を 1 時間で固定している
  - Firebase の Cache-Control ヘッダに従うのが本筋だが、シンプルさ優先
  - 鍵ローテーション後の最大 1 時間は古い鍵で検証を試みる可能性あるが、署名検証エラーになるだけで安全側

### フォローアップ作業
- AuditLog に `auth_login` / `auth_logout` を記録する（Phase 1 Task 3）
- 将来 Firebase Admin SDK が必要になったら（ユーザー削除等）`firebase-admin` 系の gem または `googleauth` で導入

## 参考リンク

- Firebase Verify ID Tokens: https://firebase.google.com/docs/auth/admin/verify-id-tokens
- jwt gem: https://github.com/jwt/ruby-jwt
- 設計書 §1.3 認証フロー
