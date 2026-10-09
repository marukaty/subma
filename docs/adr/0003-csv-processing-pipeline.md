# ADR-0003: CSV 処理パイプラインの非同期実行アーキテクチャ

- **ステータス**: 採択（Phase 4 で **本番のみ Cloud Tasks に置換** に更新）
- **日付**: 2026-04-27（初版）／ 2026-05-05（Phase 4 追記）
- **決定者**: Marin Miyazaki
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

---

## Phase 4 追記（2026-05-05）: 本番のみ Cloud Tasks に置換

### 背景

Phase 4（D-1 構成）では本番を Cloud Run + Cloud SQL の最小構成にしたい。
Sidekiq + Redis を本番で動かすには Memorystore for Redis（最低 $40/月〜）が必要となり、月額目安 $8〜17 の D-1 構成と整合しない。

### 決定

- **dev / test 環境は引き続き Sidekiq + Redis**（既存ローカル開発体験を維持）
- **production 環境のみ Cloud Tasks** に置換（HTTP push → Cloud Run 内同期実行）

新規コンポーネント:

| コンポーネント | 役割 |
|---|---|
| `CsvProcessingDispatcher` | `Rails.env.production?` で振り分け。dev/test=`ProcessCsvJob.perform_later`、prod=`Google::Cloud::Tasks` で HTTP push タスクを enqueue |
| `Internal::JobsController#process_csv` | Cloud Tasks からの POST 受け口。OIDC 検証後 `ProcessCsvJob#perform` を**同期実行** |
| `OidcVerifier` | Google OIDC ID トークンの署名・iss・aud・exp を検証 |

データフロー（本番）:

```
[ User Browser ]
  ↓ POST /csv_imports
[ CsvImportsController#create ]
  ↓ CsvProcessingDispatcher.dispatch(csv_import)
[ Cloud Tasks Queue ]  ← HTTP push タスクを enqueue
  ↓ POST /internal/jobs/process_csv (Authorization: Bearer <oidc_id_token>)
[ Internal::JobsController#process_csv ]
  ↓ OidcVerifier で検証
  ↓ ProcessCsvJob#perform を同期実行（Cloud Run プロセス内）
[ Transactions / CsvImport.status 更新 ]
```

### 採択理由

- **コスト最適**: Memorystore（$40+/月）回避、Cloud Tasks は無料枠 100 万 req/月
- **Cloud Run と親和性が高い**: スケール 0 でも Cloud Tasks 側でリトライ・タイムアウトを管理
- **OIDC 認証で安全**: 受信エンドポイント `/internal/jobs/*` は Google 発行の ID トークンのみ受け付け
- **dev 環境を破壊しない**: 既存 Sidekiq セットアップそのまま、`ProcessCsvJob` のロジックも変更なし

### ネガティブ・トレードオフ

- **dev と prod でジョブ実行経路が異なる**: 動作差を吸収するため Dispatcher を 1 箇所に集約
- **OIDC 検証の運用責任**: 公開証明書のキャッシュ TTL（1h）・rotation を考慮
- **Cloud Tasks のタイムアウト上限**: HTTP push は最大 30 分。AI 抽出が長引いた場合は分割の検討が必要

### 必要な環境変数（production のみ）

```
GCP_PROJECT_ID            # GCP プロジェクト ID
GCP_LOCATION              # 例: asia-northeast1
CLOUD_TASKS_QUEUE         # 例: process-csv
CLOUD_TASKS_TARGET_URL    # 例: https://subma-XXX.run.app/internal/jobs/process_csv
CLOUD_TASKS_SA_EMAIL      # Cloud Tasks が OIDC を発行する Service Account のメール
ENABLE_OIDC_VERIFICATION  # production では常に true（dev で疎通確認したい場合に true 化）
```

### 後続 PR

- **Phase 4 PR-B**: Terraform で Cloud Tasks Queue / Cloud Run / Cloud SQL / Secret Manager を定義
- **Phase 4 PR-C**: 実 GCP プロジェクトへのデプロイ・統合動作確認
