# ADR-0005: CSV 取り込みにおける PII 保護戦略

- **ステータス**: 採択
- **日付**: 2026-04-27
- **決定者**: なみ屋
- **関連 ADR**: ADR-0003（CSV パイプライン）、ADR-0004（AI Classifier 階層化、PR-C で作成）

## 背景

SubMa はクレジットカード明細 CSV を取り扱うため、以下のリスクがある:

- アップロード CSV にカード番号末尾・利用者名・店舗詳細などの **PII** が含まれる
- AI 判定（Claude API）に送信する際、PII が外部に漏れる可能性
- ストレージ・バックアップに残ると漏洩面積が拡大する

要件定義書 §6.1 の NFR-S-09（CSV 即削除）/ NFR-S-10（PII マスク）への準拠が必須。

## 検討した選択肢

### CSV ファイルの保存期間
- A. 永続化（AI 学習・履歴用） — **却下**: PII 集約のリスク大、要件違反
- B. 処理中のみ一時保管、完了/失敗後即削除 — **採用**

### Claude API 送信時の PII 処理
- A. 生 description をそのまま送信 — **却下**: NFR-S-10 違反
- B. 数値列（4 桁以上）を `XXXX` に置換 — **採用**（PR-C で実装）
- C. ハッシュ化 — 却下: AI が文脈を失う

## 決定

### 1. CSV ファイルの取扱（PR-B で実装）

- アップロード受信後、Active Storage で一時保管（dev: ローカルディスク `tmp/storage`、prod: GCS）
- `ProcessCsvJob` の **`ensure` ブロック**で `csv_import.purge_uploaded_file!` を呼び、成功・失敗・例外いずれの場合でも CSV ファイルを削除する
- DB の `csv_imports` レコード自体は履歴として残すが、ファイル本体は残さない

### 2. AI 送信時の PII マスキング（PR-C で実装、ADR-0004 でも触れる）

- `Classifiers::AiClassifier#mask_pii` で以下を実施:
  - `description` 内の **連続 4 桁以上の数字を `XXXX` に置換**（カード番号末尾、口座番号、電話番号）
  - ペイロードに `user_id` / `firebase_uid` / `email` を含めない
- バッチサイズ 50 件、Claude API のレスポンスに confidence と推定サービス名を含める

### 3. 開発時の制約

- `AI_USAGE_GUIDELINE.md` に従い、**本物のユーザー CSV を Claude / Claude Code に渡さない**
- テストには `spec/fixtures/csv/rakuten_sample_*.csv` のダミーデータのみ使用
- 設計レビュー時にも本物データの貼り付けを禁止

## 結果

### ポジティブ
- NFR-S-09 / NFR-S-10 の要件を満たす
- データ漏洩面積が最小化される（PII は処理中だけ存在）
- 将来 GCS に移行しても同じ Active Storage インターフェースで運用継続可能

### ネガティブ・トレードオフ
- ファイル削除後に問題があった場合の再処理は CSV を再アップロードする必要がある
- AI のマスキングは「機械的に 4 桁以上の数字」なので、特殊な PII 表現は漏れる可能性がある
  - 対策: AI 出力を表示時にレビュー画面で再度ユーザーに確認させる（PR-C）

### フォローアップ
- Phase 4: GCS 暗号化キー設定（CMEK）の検討
- Phase 5: Cloud Audit Logs で「誰がいつ何を取り込んだか」を残す

## 参考

- 要件定義書 §6.1 NFR-S-09, NFR-S-10
- 設計書 §5.1 二段階アーキテクチャ
- Anthropic Data Privacy Policy
