region = "eu-north-1"
name   = "k8s-gitops"

# Network
vpc_cidr             = "10.0.0.0/16"
azs                  = ["eu-north-1a", "eu-north-1b", "eu-north-1c"]
private_subnet_cidrs = ["10.0.0.0/19", "10.0.32.0/19", "10.0.64.0/19"]
public_subnet_cidrs  = ["10.0.96.0/24", "10.0.97.0/24", "10.0.98.0/24"]
single_nat_gateway   = true

# EKS
kubernetes_version         = "1.37"
admin_principal_arn        = "arn:aws:iam::404386756450:user/ofir-admin"
cluster_log_types          = ["audit", "authenticator"]
cluster_log_retention_days = 7
node_ami_type              = "AL2023_x86_64_STANDARD"
node_instance_types        = ["t3.medium"]
node_min_size              = 3
node_max_size              = 4
node_desired_size          = 3

# ECR and CI
ecr_repository_name      = "nodes-api"
ecr_keep_image_count     = 30
ecr_untagged_expiry_days = 1
github_repository        = "ofirtasa/kubernetes-gitops-platform"
