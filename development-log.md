# Development Log

Claude Code セッション間の引き継ぎログ。新しいエントリは**先頭**に追加する（最新が上）。

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

**完了**: （Phase 0 完了基準を満たした時点で記入）

**未完了・次回引き継ぎ**: Phase 1（Firebase Auth + セキュリティ基盤）

**使用モデル**: Sonnet

**メモ**:
- 設計書では Ruby 3.3.x 指定だったが、ローカル環境に 3.4.5 が入っていたためそちらを採用。Rails 8.1.3 と組み合わせて動作確認OK。
- 設計書では Rails 7 だったが Rails 8.1.3 に上げた（理由: 現行の安定版、Solid 系の選択肢を持ちたい、長期メンテナンス性）。
- グローバル `~/.claude/CLAUDE.md` の「Cloudflare Workers + D1 + Cloudflare Access」構成は、求人ポートフォリオ用途として合理的な例外として上書き。`subma/CLAUDE.md` に明記。
- リポジトリは Private（gakushu-system は Public 化したが、SubMa は決済関連のため Private を推奨）。
