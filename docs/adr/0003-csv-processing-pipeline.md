# ADR-0003: CSV 処理パイプラインの非同期実行アーキテクチャ

- **ステータス**: 採択（Phase 4 で再評価予定）
- **日付**: 2026-04-27
- **決定者**: なみ屋
- **関連 ADR**: ADR-0004（AI Classifier の階層化）、ADR-0005（CSV PII 保護）

## 背景

CSV 取り込みは以下の長時間処理を含み、リクエスト・レスポンスサイクル内で同期実行すべきではない:

- CSV パース（最大 5MB / 数千行）
- 規則ベース判定（ServiceTemplate との正規表現マッチ）
- パターン検出（過去 transactions の集計）
- AI 判定（Claude API、バッチ呼び出し、応答数秒〜十数秒、PR-C で実装）

設計書 §5 では「Sidekiq で非同期実行」と指定されている。

## 検討した選択肢

### A. Sidekiq + Redis（採用）
- メリット:
  - 設計書通り、ローカル開発で完結（既存 Redis を再利用）
  - Web UI（Sidekiq dashboard）が無料で監視性が高い
  - リトライ・dead set・並列度などの実績あり
- デメリット:
  - Redis 障害時にジョブが消失するリスク（永続化 OFF の場合）
  - 本番運用で別ワーカーを動かす必要がある（Cloud Run の同居 or 別サービス）

### B. Solid Queue（Rails 8 デフォルト）
- メリット: Redis 不要、DB だけで済む
- デメリット:
  - 設計書から逸脱
  - Phase 3 で大きな処理を扱う際の実績が浅い
  - Sidekiq ほどの監視ツールなし

### C. Cloud Tasks（GCP）
- メリット: Phase 4 のクラウド統合と整合
- デメリット:
  - ローカル開発が困難（エミュレータが要る）
  - Phase 3 はローカル完結したい

## 決定

**A. Sidekiq + Redis** を採用。

実装:
- `Gemfile`: `sidekiq` 追加
- `config/initializers/sidekiq.rb`: Redis URL を ENV から取得
- `config/application.rb`: ActiveJob のキューアダプタを `:sidekiq` に
- `docker-compose.yml`: `worker` サービスを追加（`bundle exec sidekiq`）
- `ProcessCsvJob` が CSV パイプラインを統合実行

## 結果

### ポジティブ
- 設計書のアーキテクチャと一致、変更不要
- Web UI 経由で worker 状態を確認可能（`/sidekiq` は将来導入予定）
- 並列度を環境ごとに調整可能

### ネガティブ・トレードオフ
- 本番運用時に Cloud Run 上で worker プロセスを別に動かす必要（Phase 4 で対応）
- Redis の運用責任が発生（Memorystore 等を Phase 4 で）

### フォローアップ
- Phase 4: Cloud Run に worker サービスを別途デプロイ。または Cloud Tasks 移行を再検討
- Sidekiq Web UI（`/sidekiq`）を Phase 5 で管理者ロールつきで公開
- リトライポリシー・dead set のモニタリング

## 参考

- 設計書 §5 CSV 処理フロー
- Sidekiq: https://github.com/sidekiqlabs/sidekiq
