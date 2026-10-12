# SubMa 開発ルール

Claude Code などの AI 支援ツールと人が共通で守る、このリポジトリの開発ルール。
技術選定の理由は [docs/adr/](./docs/adr/README.md) と [docs/infrastructure-notes.md](./docs/infrastructure-notes.md) 2 章を参照。

## 技術スタック

| 項目 | 採用 |
|---|---|
| Ruby | 3.4.5 |
| Web フレームワーク | Rails 8.1 |
| フロント | Hotwire（Turbo + Stimulus）+ importmap + Tailwind CSS |
| DB | MySQL 8.0（本番は Cloud SQL） |
| 認証 | Firebase Auth（Google SSO）+ Rails 側での ID トークン検証、ログイン許可リスト |
| ファイル保管 | Active Storage（本番は Cloud Storage、開発・テストはローカルディスク） |
| 非同期処理 | 本番は Cloud Tasks → Cloud Run の内部エンドポイント。開発・テストは Sidekiq + Redis |
| AI | Claude API（モデル名は `Classifiers::AiClassifier::MODEL`） |
| ホスティング | Cloud Run |
| IaC | Terraform（`infra/terraform/`） |
| CI/CD | GitHub Actions（Workload Identity Federation） |
| 観測 | Cloud Logging + Lograge |

## ブランチ運用

GitHub のブランチ保護を使っていないため、以下を運用で守る。

- **main に直接 push しない**。作業は必ずブランチを切り、PR 経由でマージする
- main へのマージは squash（線形履歴を保つ）
- main に強制 push しない。main を削除しない
- 作業開始時とコミット直前に、現在のブランチが `main` でないことを確認する。`main` にいたら作業を止めてブランチを切る

ブランチ名:

- 機能追加: `feature/<short-description>`
- バグ修正: `fix/<short-description>`
- インフラ: `infra/<short-description>`
- ドキュメント: `docs/<short-description>`

## PR

- `.github/pull_request_template.md` に沿って書く（変更内容・テスト・セキュリティチェック・関連 ADR）
- 設計判断を伴う変更は ADR を追加・更新する（`docs/adr/0000-template.md`）
- ドキュメントと実装の記述がずれないよう、挙動を変えた PR では README・SECURITY.md・ADR・infrastructure-notes の該当箇所も同じ PR で直す

## テスト

```bash
docker compose run --rm web bundle exec rspec
```

- 挙動を変える変更にはテストを付ける
- CI（`.github/workflows/ci.yml`）の RSpec・RuboCop・Brakeman・bundler-audit がすべて通ることをマージの条件にする

## コミットメッセージ

```
<type>(<領域>): <日本語の件名>
```

例: `fix(csv): UTF-8 BOM 付き CSV の取り込み失敗を修正`

- type: `feat` / `fix` / `docs` / `refactor` / `test` / `chore`、インフラの変更は `infra`
- 領域: `csv`・`auth`・`ai`・`classifier`・`jobs`・`infra` など、変更した機能の名前

## AI 支援開発

[AI_USAGE_GUIDELINE.md](./AI_USAGE_GUIDELINE.md) に従う。要点:

- **本物の明細 CSV を AI 支援ツールに渡さない**。テストと動作確認には `spec/fixtures/csv/` と `public/samples/` のダミーデータを使う
- `Classifiers::AiClassifier.mask_pii` の責務（4 桁以上の数字のマスク、ユーザー識別子を送らない）を削らない
- AI が生成したコードを含むコミットは、本文の末尾に `Co-Authored-By:` 行を付けて示す。件名の末尾に `[ai-assisted]` を付けてもよい
- AI が生成したコードも、人が差分を読んでからマージする。レビューでは次を必ず確認する
  - 認証・認可（`current_user` の範囲で検索しているか、検証を省く分岐がないか）
  - 秘密値・個人情報がコード・ログ・プロンプトに入っていないか
  - 設定が無いときに安全側（拒否・停止）に倒れるか
  - テストが実装の都合ではなく、意図した挙動を確かめているか

## セキュリティ

- API キー・DB の認証情報は Secret Manager から環境変数で渡す。コード・tfvars・tfstate に書かない
- CSV ファイルは取り込みが完了したら削除する（失敗時は再処理のために残し、バケットのライフサイクルで消える。ADR-0005・ADR-0007）
- Brakeman / bundler-audit の警告ゼロを保つ
- 書き込み操作は監査ログ（`AuditLog`）に残す

## 不明点・設計判断

判断に迷う点は作業を止め、PR かイシューに書いてリポジトリのオーナーに確認する。
