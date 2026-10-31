region = "eu-north-1"
name   = "k8s-gitops"

# Network
vpc_cidr             = "10.0.0.0/20"
azs                  = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
private_subnet_cidrs = ["10.0.0.0/22", "10.0.4.0/22", "10.0.8.0/22"]
public_subnet_cidrs  = ["10.0.12.0/26", "10.0.12.64/26", "10.0.12.128/26"]
single_nat_gateway   = true

# EKS
kubernetes_version         = "1.37"
admin_principal_arn        = "arn:aws:iam::404386756450:user/ofir-admin"
cluster_log_types          = ["audit", "authenticator"]
cluster_log_retention_days = 7
node_ami_type              = "AL2023_x86_64_STANDARD"
node_instance_types        = ["c7i-flex.large"] # Free plan allows only Free Tier eligible types
node_min_size              = 2                  # Cluster Autoscaler adds the third node when pods need it
node_max_size              = 4
node_desired_size          = 3

# EKS API endpoint: open to any address, because the demo network is not known in advance.
# Every request still needs IAM authentication and an EKS access entry (ADR 0003).
endpoint_public_access       = true
endpoint_public_access_cidrs = ["0.0.0.0/0"]

# Webhooks the control plane calls on nodes (security group ingress)
node_webhook_ports = {
  metrics-server     = 10251 # EKS metrics-server add-on, required by the HPA
  admission-webhooks = 9443  # Kyverno and AWS Load Balancer Controller
}

# ECR and CI
ecr_repository_name      = "nodes-api"
ecr_keep_image_count     = 30
ecr_untagged_expiry_days = 1
github_repository        = "ofirtasa/kubernetes-gitops-platform"
github_oidc_sub_prefix   = "repo:ofirtasa@169286074/kubernetes-gitops-platform@1439451897" # owner@id/repo@id

# GitOps bootstrap
argocd_chart_version      = "10.11.6"
argocd_apps_chart_version = "2.0.7"
gitops_revision           = "main"
