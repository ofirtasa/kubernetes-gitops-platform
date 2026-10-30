variable "region" {
  description = "AWS region for the state bucket."
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket that holds Terraform state for the platform stack."
  type        = string
}

variable "noncurrent_version_retention_days" {
  description = "Days to keep previous versions of state files before they expire."
  type        = number
}

variable "name" {
  description = "Project name, used for tagging."
  type        = string
}
