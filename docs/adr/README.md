# 設計記録（ADR）

主な技術判断を、背景・検討した選択肢・決定・結果の形で記録している。新しい ADR は [0000-template.md](./0000-template.md) をコピーして作る。

| 番号 | タイトル | ステータス | 日付 |
|---|---|---|---|
| [0001](./0001-firebase-auth-strategy.md) | Firebase Auth 統合方式と JWT 検証戦略 | 採択 | 2026-04-27 |
| 0002 | （欠番） | - | - |
| [0003](./0003-csv-processing-pipeline.md) | CSV 処理パイプラインの非同期実行アーキテクチャ | 採択（本番は Cloud Tasks。追記を参照） | 2026-04-27 |
| [0004](./0004-ai-classifier-tiering.md) | サブスク抽出の階層化分類器（Tier 1 / 2 / 3） | 採択 | 2026-04-28 |
| [0005](./0005-csv-pii-protection.md) | CSV 取り込みにおける PII 保護戦略 | 採択（失敗時のファイル削除は ADR-0007 で改訂） | 2026-04-27 |
| [0006](./0006-login-allowlist.md) | ログインの許可リスト（招待制） | 採択 | 2026-10-09 |
| [0007](./0007-csv-job-idempotency.md) | CSV 取り込みジョブの冪等性と再実行 | 採択 | 2026-10-11 |
| [0008](./0008-exclude-telecom-from-subscriptions.md) | 通信費をサブスクの対象外とし、Tier 1 の照合前に店名を正規化する | 採択 | 2026-10-12 |
