# Cloud SQL (MySQL 8.0) インスタンス + データベース + ユーザー
#
# 設計:
#   - db-f1-micro（個人開発には十分、$7-10/月）
#   - パブリック IP 経由（VPC connector を作らない最小構成、Cloud Run から接続）
#   - パスワードは random_password で自動生成 → Secret Manager に格納
#   - 自動バックアップは有効（無料枠内）、PITR は無効（コスト節約）
#
# 接続:
#   - Cloud Run からは Cloud SQL Auth Proxy（unix socket）経由
#     → Cloud Run service の volumes/volume_mounts で connection_name を渡す
#
# [ai-assisted]

# ---------- パスワード自動生成 ----------

resource "random_password" "cloud_sql_app" {
  length  = 32
  special = true
  # MySQL の identifier として安全な文字種に制限
  override_special = "!@#%^&*()-_=+[]{}<>?"
}

# ---------- インスタンス ----------

resource "google_sql_database_instance" "main" {
  name             = "${var.app_name}-${var.environment}"
  database_version = "MYSQL_8_0"
  region           = var.region

  settings {
    tier              = var.cloud_sql_tier
    availability_type = "ZONAL" # 個人開発規模なので REGIONAL（高可用）にせずコスト節約
    disk_size         = 10      # GB（最小）
    disk_type         = "PD_SSD"
    disk_autoresize   = true

    backup_configuration {
      enabled                        = true
      start_time                     = "18:00" # JST 03:00 相当
      point_in_time_recovery_enabled = false   # コスト節約
      backup_retention_settings {
        retained_backups = 7
        retention_unit   = "COUNT"
      }
    }

    ip_configuration {
      ipv4_enabled = true
      # 公開アクセスを許可するが、authorized_networks は空 → Cloud SQL Proxy 経由のみ受け付ける
      authorized_networks {
        name  = "no-direct-access"
        value = "127.0.0.1/32"
      }
    }

    user_labels = local.common_labels

    # 開発時にうっかり消さないようガード
    deletion_protection_enabled = true
  }

  # Terraform レベルでも消去ガード
  deletion_protection = true

  depends_on = [google_project_service.required_apis]
}

# ---------- データベース ----------

resource "google_sql_database" "main" {
  name      = var.cloud_sql_database_name
  instance  = google_sql_database_instance.main.name
  charset   = "utf8mb4"
  collation = "utf8mb4_0900_ai_ci"
}

# ---------- アプリケーションユーザー ----------

resource "google_sql_user" "app" {
  name     = var.cloud_sql_user_name
  instance = google_sql_database_instance.main.name
  password = random_password.cloud_sql_app.result
  host     = "%" # Cloud SQL Proxy 経由ではホスト制限が機能しないため `%`
}

# ---------- 出力（Cloud Run の env で使う） ----------

output "cloud_sql_connection_name" {
  description = "Cloud SQL connection name（Cloud Run の volume_mounts で使う）"
  value       = google_sql_database_instance.main.connection_name
}

output "cloud_sql_database_name" {
  description = "Database 名"
  value       = google_sql_database.main.name
}

output "cloud_sql_user_name" {
  description = "アプリ用ユーザー名"
  value       = google_sql_user.app.name
}
