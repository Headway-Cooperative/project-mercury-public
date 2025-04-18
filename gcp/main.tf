terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
  }
}

provider "google" {
  project = var.projectId
}

variable "projectId" {
}

variable "datasetName" {
}

resource "google_service_account" "account" {
  account_id   = "mercury-sa"
  display_name = "Mercury Service Account"
}

resource "google_project_iam_member" "bigquery_data_viewer" {
  project = var.projectId
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:mercury-accessor-sa@mercuryaccessor.iam.gserviceaccount.com"
  condition {
    title      = "only billing access"
    expression = "resource.name == 'projects/${var.projectId}/datasets/${var.datasetName}'"
  }
}

resource "google_project_iam_member" "bigquery_job_user" {
  project = var.projectId
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:mercury-accessor-sa@mercuryaccessor.iam.gserviceaccount.com"
  condition {
    title      = "only billing access"
    expression = "resource.name == 'projects/${var.projectId}/datasets/${var.datasetName}'"
  }
}
