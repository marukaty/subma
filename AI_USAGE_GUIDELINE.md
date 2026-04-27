# AI 利用ガイドライン

> **本ファイルは Phase 0 の雛形です。本格整備は Phase 1 で行います。**

## 適用範囲

このガイドラインは、SubMa の開発・運用において以下の AI 利用すべてに適用される:

- Anthropic Claude API（本番アプリ内のサブスク自動抽出・診断機能）
- Claude Code CLI / Claude Desktop による開発支援
- claude.ai チャットによる設計相談・コードレビュー

## 大原則（Phase 1 で詳細化）

### 1. 機密情報をプロンプトに含めない
- API キー、パスワード、本番 DB 認証情報を AI に送らない
- 環境変数は Secret Manager 経由のみ、コード直書き禁止

### 2. CSV データの取扱
- **本物のユーザー CSV を Claude / Claude Code に渡さない**
- 開発中も常にダミーデータを使う
- 本番アプリ内で Claude API に CSV データを送る際は、`AiClassifier#mask_pii` で PII をマスクする（NFR-S-10）

### 3. PII マスキングの責務
- `AiClassifier#mask_pii` の責務を勝手に削らない・簡略化しない
- カード番号末尾、口座番号、電話番号などの数値列は `XXXX` 等で置換

### 4. リポジトリ管理ルール
- AI 生成コードのコミットメッセージに `[ai-assisted]` タグを付ける
- 使用モデル（Sonnet / Opus）を `development-log.md` に記録

### 5. AI 出力の検証
- AI 判定（サブスク抽出・診断）は **あくまで提案** として扱う
- ユーザーがレビュー画面で必ず確認・修正できる UI を提供する
- AI のハルシネーションを前提にした設計

## 使用モデル

- **本番アプリ内**: `claude-sonnet-4-20250514`（コスト・速度のバランス）
- **開発支援**: 主に Sonnet、複雑な設計判断時のみ Opus

## 参照

- 要件定義書 §6.1 NFR-S-08, NFR-S-10
- 設計書 §3.2 AI Classifier（Tier 3）
