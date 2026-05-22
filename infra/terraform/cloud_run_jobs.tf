resource "google_cloud_run_v2_job" "migrate" {
  name     = "${var.app_name}-web-migrate"
  location = var.region

  labels = local.common_labels

  template {
    template {
      service_account = google_service_account.cloud_run.email

      # Cloud SQL Auth Proxy（unix socket）
      volumes {
        name = "cloudsql"
        cloud_sql_instance {
          instances = [google_sql_database_instance.main.connection_name]
        }
      }

      containers {
        image = var.container_image

        # rails db:prepare を実行（マイグレーション + seeds + schema_cache の dump）
        # 失敗してもデプロイ全体は止めない設計（初回 only な部分含むため）
        command = ["./bin/rails"]
        args    = ["db:prepare"]

        resources {
          limits = {
            cpu    = "1000m"
            memory = "512Mi"
          }
        }

        volume_mounts {
          name       = "cloudsql"
          mount_path = "/cloudsql"
        }

        # ----- Cloud Run service と同じ env -----
        env {
          name  = "RAILS_ENV"
          value = "production"
        }

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

        env {
          name = "RAILS_MASTER_KEY"
          value_source {
            secret_key_ref {
              secret  = google_secret_manager_secret.subma["rails-master-key"].secret_id
              version = "latest"
            }
          }
        }
      }

      max_retries = 1
      timeout     = "300s"
    }
  }

  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret_version.subma,
    google_secret_manager_secret_iam_member.cloud_run_accessor,
  ]

  lifecycle {
    ignore_changes = [
      template[0].template[0].containers[0].image,
    ]
  }
}
