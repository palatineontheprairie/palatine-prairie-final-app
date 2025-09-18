terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

variable "project_id" {
  type        = string
  description = "The Google Cloud project ID."
}

variable "region" {
  type        = string
  description = "The Google Cloud region for resources."
  default     = "us-central1"
}

variable "github_repo" {
  type        = string
  description = "The GitHub repository in user/repo format."
}

# --- Secure Login (Workload Identity Federation) ---

resource "google_service_account" "github_actions_sa" {
  account_id   = "marcus-deployer"
  display_name = "Marcus Deployer Service Account"
}

resource "google_iam_workload_identity_pool" "github_pool" {
  workload_identity_pool_id = "marcus-github-pool"
  display_name              = "Marcus GitHub Actions Pool"
}

resource "google_iam_workload_identity_pool_provider" "github_provider" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github_pool.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub Actions Provider"
  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }
}

resource "google_service_account_iam_member" "github_actions_wif_user" {
  service_account_id = google_service_account.github_actions_sa.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github_pool.name}/attribute.repository/${var.github_repo}"
}

# --- Project Permissions for the Service Account ---

resource "google_project_iam_member" "storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_project_iam_member" "cloudfunctions_developer" {
  project = var.project_id
  role    = "roles/cloudfunctions.developer"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

resource "google_project_iam_member" "secretmanager_admin" {
  project = var.project_id
  role    = "roles/secretmanager.admin"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# --- Application Secrets ---

resource "google_secret_manager_secret" "secrets" {
  for_each = toset([
    "TWITTER_API_KEY",
    "TWITTER_API_SECRET",
    "OPENAI_API_KEY",
    "AMAZON_ASSOCIATE_TAG"
  ])
  secret_id = each.key
  replication {
    automatic = true
  }
}
