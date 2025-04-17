terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 6.0.0"
    }
  }
}

provider "google" {
  project = ""
}

variable "datasetName" {
}

variable "tagNames" {
  default = ""
}

resource "google_service_account" "account" {
  account_id   = "mercury-sa"
  display_name = "Mercury Service Account"
}

resource "random_id" "default" {
  byte_length = 8
}

resource "google_storage_bucket" "bucket" {
  name                        = "mercury-computing-${random_id.default.hex}"
  location                    = "US"
  uniform_bucket_level_access = true
}

data "archive_file" "default" {
  type        = "zip"
  output_path = "/tmp/mercury-billing-export.zip"
  excludes = [
    "*.tf",
    ".terraform*",
    "terraform*"
  ]
  source_dir = "."
}

resource "google_storage_bucket_object" "object" {
  name   = "mercury-billing-export-${data.archive_file.default.output_md5}.zip"
  bucket = google_storage_bucket.bucket.name
  source = data.archive_file.default.output_path
  depends_on = [
    google_storage_bucket.bucket,
    data.archive_file.default
  ]
}

resource "google_cloudfunctions2_function" "function" {
  name        = "mercury-billing-export"
  location    = "us-west1"
  description = "Send Carbon Accounting Data from your GCP account to Mercury Computing."

  build_config {
    runtime     = "nodejs22"
    entry_point = "exportData"
    source {
      storage_source {
        bucket = google_storage_bucket.bucket.name
        object = google_storage_bucket_object.object.name
      }
    }
  }

  service_config {
    min_instance_count    = 1
    available_memory      = "256M"
    timeout_seconds       = 60
    service_account_email = google_service_account.account.email
  }

  depends_on = [google_service_account.account]
}

resource "google_project_iam_member" "bigquery_data_viewer" {
  project = google_cloudfunctions2_function.function.project
  role    = "roles/bigquery.dataViewer"
  member  = google_service_account.account.member
}

resource "google_project_iam_member" "bigquery_job_user" {
  project = google_cloudfunctions2_function.function.project
  role    = "roles/bigquery.jobUser"
  member  = google_service_account.account.member
}

resource "google_project_iam_member" "storage_object_creator" {
  project = google_cloudfunctions2_function.function.project
  role    = "roles/storage.objectCreator"
  member  = google_service_account.account.member
}

resource "google_cloudfunctions2_function_iam_member" "invoker" {
  project        = google_cloudfunctions2_function.function.project
  location       = google_cloudfunctions2_function.function.location
  cloud_function = google_cloudfunctions2_function.function.name
  role           = "roles/cloudfunctions.invoker"
  member         = google_service_account.account.member
}

resource "google_cloud_run_service_iam_member" "cloud_run_invoker" {
  project  = google_cloudfunctions2_function.function.project
  location = google_cloudfunctions2_function.function.location
  service  = google_cloudfunctions2_function.function.name
  role     = "roles/run.invoker"
  member   = google_service_account.account.member
}

resource "google_cloud_scheduler_job" "invoke_cloud_function" {
  name        = "invoke-mercury-billing-export"
  description = "Schedule the HTTPS trigger for mercury-billing-export"
  schedule    = "47 11 * * *" # every day at 11:47
  project     = google_cloudfunctions2_function.function.project
  region      = google_cloudfunctions2_function.function.location

  http_target {
    uri         = google_cloudfunctions2_function.function.service_config[0].uri
    http_method = "POST"
    headers = {
      "Content-Type" : "application/json"
    }
    body = base64encode("{\"projectId\":\"${google_service_account.account.project}\",\"tableName\":\"${var.datasetName}\",\"tagNames\":\"${var.tagNames}\"}")
    oidc_token {
      audience              = "${google_cloudfunctions2_function.function.service_config[0].uri}/"
      service_account_email = google_service_account.account.email
    }
  }
}
