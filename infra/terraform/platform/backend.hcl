# terraform init -backend-config=backend.hcl
bucket       = "k8s-gitops-tfstate-404386756450"
key          = "platform/terraform.tfstate"
region       = "eu-north-1"
encrypt      = true
use_lockfile = true
