terraform {
  required_version = ">= 1.10"

  required_providers {
    elasticstack = {
      source  = "elastic/elasticstack"
      version = "~> 0.16"
    }
  }
}

provider "elasticstack" {
  kibana {
    endpoints = [var.kibana_url]
    api_key   = var.kibana_api_key
  }
}
