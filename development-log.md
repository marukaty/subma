# Development Log

Claude Code セッション間の引き継ぎログ。新しいエントリは**先頭**に追加する（最新が上）。

---

## 2026-04-27 (Phase 1 / Task 1-4)

**着手内容**: Phase 1（セキュリティ基盤 & Firebase Auth）の全タスク

**完了**:
- Task 1: Firebase Auth（Google SSO）統合
  - `FirebaseAuthVerifier` 自前 JWT 検証（RS256, iss/aud/exp/iat/sub, 公開証明書 1h キャッシュ）
  - `User` モデル + マイグレーション
  - `AuthController` (sign_in / sign_out)
  - 簡易ログイン UI + 空ダッシュボード
  - Importmap 経由で gstatic CDN から Firebase Web SDK 読み込み（JSPM 経由は壊れる）
  - **実 Google アカウントでログイン成功確認**（「Marin M さん」表示）
- Task 2: セキュリティ基盤
  - rack-attack（/auth/sign_in 5/min, /csv_imports 10/5min, 全般 60/10s）
  - secure_headers（CSP / HSTS / X-Frame-Options 等）
  - lograge（JSON 構造化ログ、user_id / request_id を payload に追加）
  - brakeman / bundler-audit（**0 warnings, 0 vulnerabilities**）
  - GitHub Actions CI: scan_ruby + lint + test の 3 ジョブ
- Task 3: AuditLog
  - `audit_logs` テーブル（user nullable, action / resource_type / resource_id / ip_address / user_agent）
  - `ApplicationController#record_audit_log` after_action（GET 以外を自動記録）
  - `AuthController` で `auth.sign_in / sign_in_failed / sign_out` を明示的記録
  - RSpec で AuditLog 記録を検証
- Task 4: ドキュメント本格整備
  - SECURITY.md 全面書き直し（脅威モデル T-01〜T-09、対策一覧、CSV / AI / 監査ログ各方針）
  - AI_USAGE_GUIDELINE.md 全面書き直し（CSV PII マスキング規則、AI 生成コード管理、開発時チェックリスト）
- ADR-0001 firebase-auth-strategy
- RSpec: **32 examples, 0 failures**

**Phase 1 完了基準**:
- ✅ Google ログイン → ダッシュボード（実機確認済み）
- ✅ Brakeman 警告ゼロ
- ✅ Rack::Attack 稼働
- ✅ AuditLog 記録（テスト済み: sign_in / sign_in_failed / sign_out）
- ✅ SECURITY.md / AI_USAGE_GUIDELINE.md 整備

**未完了・次回引き継ぎ**: Phase 2（ドメインモデル + サブスク CRUD + ダッシュボード）

**使用モデル**: Sonnet（Opus 切替なし）

**メモ**:
- Importmap で Firebase を vendor 取り込みは動的 chunk 読込で 404 になる罠あり → gstatic CDN 直参照で解決
- Rails 8 のデフォルト `config.hosts` は本番だけでなく test でも有効、test.rb に `config.hosts << "www.example.com"` 追加
- docker compose で `RAILS_ENV=development` が rspec に伝搬する罠 → rails_helper.rb で強制上書き
- `allow_browser :modern` は test ではスキップ
- 次回の `feature/phase2-...` ブランチを切る前に、本 PR を develop 相当（main）にマージしてから

---

## 2026-04-27 (Phase 0 / Task 1-4)

**着手内容**: Phase 0（プロジェクト初期化）の全タスク
- Rails 8.1.3 / Ruby 3.4.5 で `rails new subma` 実行
- 構成: `--database=mysql --css=tailwind --skip-javascript --skip-solid -T --skip-bootsnap`
  - JavaScript は Phase 2 で Vite を手動導入予定（Rails 8 は importmap/esbuild/bun のみネイティブサポート）
  - Solid Queue/Cache/Cable はスキップ。代わりに Sidekiq + Redis を Phase 3 で導入
- RSpec / Capybara / Selenium インストール
- Docker 環境（Dockerfile.dev / docker-compose.yml: Rails + MySQL 8 + Redis 7）
- 基本ドキュメント雛形（README, SECURITY, AI_USAGE_GUIDELINE, CLAUDE.md, ADR テンプレ）
- GitHub Private リポ作成、main 保護、Issue/PR テンプレ

**完了**:
- Rails 8.1.3 / Ruby 3.4.5 プロジェクト生成
- RSpec 導入（0 examples, 0 failures pass）
- Docker 開発環境（`docker compose up` で `http://localhost:3010` HTTP 200 確認）
- 基本ドキュメント雛形すべて配置
- GitHub Private リポ作成 + main へ初回 push 完了（https://github.com/marukaty/subma）
- Issue / PR テンプレ配置

**未完了・次回引き継ぎ**:
- ブランチ保護ルールが GitHub 無料 Private では設定不可。**運用規律で担保する方針**を採用（CLAUDE.md に明記）
- Phase 1（Firebase Auth + セキュリティ基盤）から開始
- 次回 Claude Code セッションは必ず `git checkout -b feature/phase1-...` でブランチを切ってから作業開始すること

**使用モデル**: Sonnet

**メモ**:
- 設計書では Ruby 3.3.x 指定だったが、ローカル環境に 3.4.5 が入っていたためそちらを採用。Rails 8.1.3 と組み合わせて動作確認OK。
- 設計書では Rails 7 だったが Rails 8.1.3 に上げた（理由: 現行の安定版、Solid 系の選択肢を持ちたい、長期メンテナンス性）。
- グローバル `~/.claude/CLAUDE.md` の「Cloudflare Workers + D1 + Cloudflare Access」構成は、求人ポートフォリオ用途として合理的な例外として上書き。`subma/CLAUDE.md` に明記。
- リポジトリは Private（gakushu-system は Public 化したが、SubMa は決済関連のため Private を推奨）。
