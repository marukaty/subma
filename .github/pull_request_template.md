## 概要

このPRで何が変わるか、なぜ変えるか（1-3文）。

関連 Issue: #

## 変更内容

-
-

## テスト

- [ ] RSpec 追加・更新済み
- [ ] `docker compose run --rm web bundle exec rspec` が通る

## セキュリティチェック

- [ ] API キー / 秘密情報をコミットしていない
- [ ] PII を AI に送る箇所があれば `mask_pii` を経由している
- [ ] CSV を扱う箇所があれば、取り込み完了時に削除している（NFR-S-09、ADR-0007）

## スクリーンショット（UI 変更がある場合）

## 参照 ADR

- 該当する設計判断があれば ADR を作成・リンク

## チェックリスト

- [ ] コミットメッセージは `<type>(<領域>): <件名>` 形式
- [ ] AI 生成コードを含むコミットには `Co-Authored-By:` 行を付けた
- [ ] 挙動を変えた場合、README・SECURITY.md・ADR・infrastructure-notes の該当箇所も直した
