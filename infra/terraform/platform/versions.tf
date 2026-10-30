terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.71"
    }
  }

  # Values in backend.hcl; credentials come from AWS_PROFILE.
  backend "s3" {}
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project    = var.name
      Stack      = "platform"
      ManagedBy  = "terraform"
      Repository = var.github_repository
    }
  }
}
