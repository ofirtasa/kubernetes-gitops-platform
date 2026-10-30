terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # Migrated into the bucket after the first apply; values in backend.hcl.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.name
      Stack     = "bootstrap"
      ManagedBy = "terraform"
    }
  }
}
