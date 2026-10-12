# Firestore Database 定義（v2 用。現在アプリからは使っていない）
#
# 用途（v2 で実装予定）:
#   - リアルタイム通知（CSV 処理進捗を WebSocket で push する代替）
#   - 軽い設定値・キャッシュ（Cloud SQL を叩かずに済むホットデータ）
#
# 現在は Database リソースだけを宣言している（コレクション・ルールは定義していない）。
#
# [ai-assisted]

resource "google_firestore_database" "default" {
  project     = var.project_id
  name        = "(default)"
  location_id = var.region
  type        = "FIRESTORE_NATIVE"

  # 削除されにくくする
  delete_protection_state = "DELETE_PROTECTION_ENABLED"

  depends_on = [google_project_service.required_apis]
}
