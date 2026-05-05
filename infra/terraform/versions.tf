# Terraform / プロバイダのバージョン固定
#
# Terraform 本体は 1.10 系以上。
# Google プロバイダは 6.x 系で固定（Cloud Run v2 / Workload Identity Federation 等が安定して使える）。
#
# [ai-assisted]

terraform {
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.20"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 6.20"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
