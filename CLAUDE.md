# SubMa プロジェクト固有 ルール

このファイルは **グローバル `~/.claude/CLAUDE.md` のルールを SubMa プロジェクト内では意図的に上書き** するものです。

## グローバルルールを上書きする理由

グローバルでは「Cloudflare Workers + D1 + Cloudflare Access + Next.js」を必須構成と定義しているが、SubMa は **リベシティ求人（Rails 開発メンバー）応募ポートフォリオ** を主目的としており、求人の必須条件「Firebase / Google Cloud」「Rails 3年以上」を満たすため、以下構成を採用する（合理的な例外）。

## SubMa の固定構成

| 項目 | 採用 |
|---|---|
| Ruby | 3.4.5 |
| Webフレームワーク | Rails 8.1.x（設計書は 7 指定だが 8 にアップグレード） |
| DB（永続） | MySQL 8.0（Cloud SQL） |
| DB（リアルタイム） | Firestore |
| 認証 | Firebase Auth（Google SSO） |
| ホスティング | Cloud Run |
| 非同期ジョブ | Sidekiq + Redis |
| 定期処理 | Cloud Scheduler + Cloud Tasks |
| フロント | Hotwire（Turbo + Stimulus）+ Vite + Tailwind |
| AI | Claude API（claude-sonnet-4-20250514） |
| IaC | Terraform |
| CI/CD | GitHub Actions（OIDC + Workload Identity Federation） |
| 観測 | Cloud Logging + Cloud Monitoring + Lograge |

## 守るべき設計ルール（要件・設計書より）

### 必読
- `SubMa_Requirements.md`（要件定義書 / 親フォルダの docx）
- `SubMa_Design.md`（設計書 兼 開発指示書 / 親フォルダの docx）
- `development-log.md`（最新エントリで前回コンテキスト把握）

### セキュリティ（NFR-S 系）
- **CSV ファイルは処理後即削除**、永続化禁止（NFR-S-09）
- Claude API 送信時はユーザー識別子除外、CSV 内 PII はマスク（NFR-S-10）
- API キー・DB 認証情報は **Secret Manager 経由のみ**、コード直書き禁止
- Brakeman / bundler-audit を CI で実行、警告ゼロを維持
- 監査ログを全書き込み操作で記録（AuditLog モデル）

### AI 利用（AI_USAGE_GUIDELINE.md に従う）
- **本物のユーザー CSV を Claude / Claude Code に渡さない**。常にダミーデータを使う
- `AiClassifier#mask_pii` の責務を勝手に削らない
- AI 生成コードはコミットメッセージに `[ai-assisted]` タグ
- 使用モデル（Sonnet / Opus）を development-log.md に記録

### コミットメッセージ
```
<type>(phase<N>): <subject>
```
例: `feat(phase3): Add Rakuten CSV adapter`

type: `feat`, `fix`, `docs`, `refactor`, `test`, `chore`, `infra`

### 不明点・設計判断
作業を止めて development-log.md に質問記録、なみさんに確認。**勝手に進めない**。

## セッション開始時の手順

1. `subma/CLAUDE.md`（本ファイル）を読む
2. `SubMa_Design.md`（設計書）と `SubMa_Requirements.md`（要件）を必要に応じて参照（親フォルダ `/Users/marin/Dropbox/work/namiya/SubMa/` の docx）
3. `development-log.md` の最新エントリで前回コンテキスト把握
4. 現在の Phase / タスクを宣言してから作業開始

## セッション終了時の手順

`development-log.md` に追記:

```
## YYYY-MM-DD HH:MM (Phase X / Task Y)
**着手内容**:
**完了**:
**未完了・次回引き継ぎ**:
**使用モデル**: Sonnet / Opus
**メモ**:
```

## リポジトリ公開設定

**Private**（CLAUDE.md グローバルルール通り）。理由: ポートフォリオ用途は別サイト（namiya.dev）で担保しており、Stripe Webhook secret 等の誤コミットリスクを下げるため Private が安全。コードを見せたい時は個別に Collaborator 招待する。

## ブランチ運用規律（GitHub 無料プランの制約により**人とAIで担保**）

GitHub 無料プランの Private リポではブランチ保護ルール / Rulesets を設定できないため、以下を **必ず** 守ること:

### 絶対ルール
- **main に直接 push しない**。常に feature ブランチを切ってPR経由でマージ
- main へのマージは **必ず PR 経由**（squash or rebase merge 推奨、線形履歴維持）
- 強制 push（`git push --force` / `--force-with-lease`）を main に行わない
- main の削除を行わない

### ブランチ命名
- 新規機能: `feature/<phase><N>-<short-description>`（例: `feature/phase1-firebase-auth`）
- バグ修正: `fix/<short-description>`（例: `fix/csv-parser-encoding`）
- インフラ: `infra/<short-description>`
- ドキュメント: `docs/<short-description>`

### Claude Code（私）の自動チェック責務
私は作業開始時に以下を確認する:
1. 現在のブランチが `main` でないこと
2. もし `main` にいたら、必ず先に `git checkout -b feature/...` でブランチを切ってから作業開始
3. コミット直前にも再確認、`main` であれば作業を止めて Nami に報告

### 将来の検討
- GitHub Pro 有料化（月 $4 程度）でブランチ保護を物理的にかけられる
- Phase 1 で「main に直接 push されたら CI で失敗させる」GitHub Actions を導入検討
