# Cloud Run service 定義（subma-web）
#
# 設計:
#   - min-instances = 0（コールドスタート許容、コスト最優先）
#   - max-instances = 3（個人開発規模）
#   - Cloud SQL Auth Proxy を unix socket 経由で接続（volumes）
#   - Secret Manager の値を環境変数として注入
#   - 公開アクセス（ingress: all、authenticated 不要）— 本物のアプリは内部で Firebase Auth
#   - Internal::JobsController は Cloud Run service レベルでは公開だが、
#     OIDC 検証で Cloud Tasks SA からのみ受け付け（アプリ側で担保）
#
# [ai-assisted]

resource "google_cloud_run_v2_service" "web" {
  name     = "${var.app_name}-web"
  location = var.region
  ingress  = "INGRESS_TRAFFIC_ALL"

  labels = local.common_labels

  template {
    service_account = google_service_account.cloud_run.email

    scaling {
      min_instance_count = 0
      max_instance_count = 3
    }

    # Cloud SQL を unix socket でマウント
    volumes {
      name = "cloudsql"
      cloud_sql_instance {
        instances = [google_sql_database_instance.main.connection_name]
      }
    }

    containers {
      image = var.container_image

      ports {
        # Rails + thruster は PORT 環境変数を尊重するため、Cloud Run のデフォルト 8080 で OK
        container_port = 8080
      }

      resources {
        limits = {
          cpu    = "1000m"
          memory = "512Mi"
        }
        cpu_idle          = true # 非アクティブ時は CPU 課金停止
        startup_cpu_boost = true
      }

      # Cloud SQL Auth Proxy ソケットをマウント
      volume_mounts {
        name       = "cloudsql"
        mount_path = "/cloudsql"
      }

      # ----- 環境変数 -----
      env {
        name  = "RAILS_ENV"
        value = "production"
      }

      env {
        name  = "PORT"
        value = "8080"
      }

      # database.yml で参照する想定の環境変数
      env {
        name  = "DATABASE_HOST"
        value = "/cloudsql/${google_sql_database_instance.main.connection_name}"
      }

      env {
        name  = "DATABASE_NAME"
        value = google_sql_database.main.name
      }

      env {
        name  = "DATABASE_USERNAME"
        value = google_sql_user.app.name
      }

      env {
        name = "DATABASE_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.subma["cloud-sql-app-password"].secret_id
            version = "latest"
          }
        }
      }

      # Rails master.key
      env {
        name = "RAILS_MASTER_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.subma["rails-master-key"].secret_id
            version = "latest"
          }
        }
      }

      # Anthropic API
      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.subma["anthropic-api-key"].secret_id
            version = "latest"
          }
        }
      }

      # Firebase Auth
      env {
        name  = "FIREBASE_PROJECT_ID"
        value = var.firebase_project_id
      }

      env {
        name  = "FIREBASE_AUTH_DOMAIN"
        value = var.firebase_auth_domain
      }

      env {
        name = "FIREBASE_WEB_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.subma["firebase-web-api-key"].secret_id
            version = "latest"
          }
        }
      }

      # Cloud Tasks 設定（CsvProcessingDispatcher が利用）
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }

      env {
        name  = "GCP_LOCATION"
        value = var.region
      }

      env {
        name  = "CLOUD_TASKS_QUEUE"
        value = google_cloud_tasks_queue.process_csv.name
      }

      # CLOUD_TASKS_TARGET_URL は Cloud Run の URL に依存するため、
      # Terraform 上では URL 取得後に再 apply で設定する。
      # PR-C のデプロイスクリプトで設定する想定。
      # ここではプレースホルダ（実 URL は実 apply 時に上書き）。
      env {
        name  = "CLOUD_TASKS_TARGET_URL"
        value = "https://placeholder-set-after-first-apply.example.com/internal/jobs/process_csv"
      }

      env {
        name  = "CLOUD_TASKS_SA_EMAIL"
        value = google_service_account.cloud_tasks.email
      }

      env {
        name  = "ENABLE_OIDC_VERIFICATION"
        value = "true"
      }

      # CSV 一時保存バケット
      env {
        name  = "CSV_TEMP_BUCKET"
        value = google_storage_bucket.csv_temp.name
      }
    }

    # 起動タイムアウト（Rails boot に余裕）
    timeout = "60s"
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret_version.subma,
    google_secret_manager_secret_iam_member.cloud_run_accessor,
  ]

  # コンテナイメージ・URL 関連は CI からの再 apply で更新するため
  # Terraform の差分検出をスキップしたいフィールドがあれば lifecycle.ignore_changes に追加
  lifecycle {
    ignore_changes = [
      # CI/CD で image を入れ替えた後、Terraform 側の値で巻き戻さないようにする
      template[0].containers[0].image,
    ]
  }
}

# ===================================================================
# Cloud Run の公開アクセス設定（allUsers が invoker）
# ===================================================================
# 公開 LP / アプリ画面なので allUsers に invoker を付与。
# Internal::JobsController の OIDC 検証は**アプリレイヤー**で担保。

resource "google_cloud_run_v2_service_iam_member" "public" {
  project  = var.project_id
  location = google_cloud_run_v2_service.web.location
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# Cloud Tasks SA は別途 invoker 権限を持つ（公開向け and Cloud Tasks 由来両方）
resource "google_cloud_run_v2_service_iam_member" "cloud_tasks_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_service.web.location
  name     = google_cloud_run_v2_service.web.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.cloud_tasks.email}"
}

# ---------- 出力 ----------

output "cloud_run_url" {
  description = "Cloud Run service の HTTPS URL（CLOUD_TASKS_TARGET_URL の元になる）"
  value       = google_cloud_run_v2_service.web.uri
}

output "cloud_tasks_target_url" {
  description = "Internal::JobsController#process_csv の URL（手動で env を上書きする用）"
  value       = "${google_cloud_run_v2_service.web.uri}/internal/jobs/process_csv"
}
