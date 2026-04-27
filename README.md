# SubMa - Subscription Mapping

> 散らばったサブスクを一枚の地図にまとめる、個人向けサブスクリプション管理アプリ

「気づいたら払い続けていた」を、「全部見えていて、選んで払っている」状態に変える。

## 概要

- **ターゲット**: 複数のサブスクサービスを利用していて、「何にいくら払っているか把握できていない」個人ユーザー
- **コア機能**: 手動登録、CSV取り込み、AIによるサブスク自動抽出、ダッシュボード（月額・年額・カテゴリ別）、引落日カレンダー、メール通知
- **差別化**: クレジットカード明細 CSV をアップロードすると、規則ベース＋Claude API でサブスクを自動抽出

## 技術スタック

- Ruby 3.4.5 / Rails 8.1
- MySQL 8.0（Cloud SQL）+ Firestore（リアルタイム通知・処理進捗）
- Hotwire（Turbo + Stimulus）+ Vite + Tailwind CSS
- Firebase Auth（Google SSO）
- Sidekiq + Redis（非同期処理）
- Anthropic Claude API（claude-sonnet-4-20250514）
- Cloud Run / Cloud Storage / Secret Manager / Cloud Tasks / Cloud Scheduler
- Terraform / GitHub Actions（OIDC）

詳細は `docs/adr/` を参照。

## 開発開始

### 前提
- Docker / Docker Compose
- （ローカル直接実行する場合）Ruby 3.4.5 / MySQL 8.0 / Redis

### Docker での起動（推奨）
```bash
docker compose up
```
ブラウザで `http://localhost:3000` を開く。

### ローカル直接起動
```bash
bundle install
bin/rails db:prepare
bin/rails server
```

### テスト
```bash
docker compose run --rm web bin/rspec
# または
bin/rspec
```

## ドキュメント

- `../SubMa_Requirements.md.docx` - 要件定義書（親フォルダ）
- `../SubMa_Design.md.docx` - 設計書（親フォルダ）
- [SECURITY.md](./SECURITY.md) - 脅威モデル・対策一覧
- [AI_USAGE_GUIDELINE.md](./AI_USAGE_GUIDELINE.md) - Claude / AI 利用ガイドライン
- [development-log.md](./development-log.md) - 開発セッション引き継ぎログ
- [docs/adr/](./docs/adr/) - 主要技術判断（ADR）

## ライセンス

Private（個人ポートフォリオ）。
