# セキュリティ方針

> **本ファイルは Phase 0 の雛形です。本格整備は Phase 1 で行います。**

## 概要

SubMa はクレジットカード明細 CSV を取り扱う性質上、PII（Personally Identifiable Information / 個人を特定できる情報）保護を最優先に設計する。

## 脅威モデル（Phase 1 で詳細化）

- CSV ファイル経由の PII 漏洩
- Claude API 経由の PII 流出
- 認証バイパス
- セッションハイジャック
- CSRF / XSS / SQLインジェクション（OWASP Top 10）
- レート制限を伴わないエンドポイントへの攻撃

## 対策一覧（Phase 1 で実装）

- [ ] OWASP Top 10 (2021) 対策の実装と文書化（NFR-S-01）
- [ ] CI 毎の Brakeman / bundler-audit 実行（NFR-S-02）
- [ ] Rack::Attack によるレート制限（NFR-S-03）
- [ ] secure_headers による CSP / HSTS / X-Frame-Options（NFR-S-04）
- [ ] AuditLog の全書き込み操作記録（NFR-S-05）
- [ ] Firestore セキュリティルールによるユーザー間データ分離（NFR-S-06）
- [ ] Secret Manager による API / DB 認証情報管理（NFR-S-07）
- [ ] AI_USAGE_GUIDELINE.md による Claude / AI 利用時の機密情報取扱ルール明文化（NFR-S-08）
- [ ] **CSV ファイルは処理後即削除、永続化禁止**（NFR-S-09）
- [ ] Claude API へ送るデータからユーザー識別子を除外、PII 部分はマスク（NFR-S-10）

## 脆弱性報告先

（Phase 1 で記載）

## 参照

- 要件定義書 §6.1 セキュリティ要件
- AI_USAGE_GUIDELINE.md
