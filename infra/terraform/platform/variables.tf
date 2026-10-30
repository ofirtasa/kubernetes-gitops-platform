variable "region" {
  description = "AWS region for all platform resources."
  type        = string
}

variable "name" {
  description = "Name prefix for the VPC, EKS cluster and related resources."
  type        = string
}

# Network

variable "vpc_cidr" {
  description = "CIDR block of the VPC."
  type        = string
}

variable "azs" {
  description = "Availability zones, one subnet of each type per zone."
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "Private subnets for nodes and pods, one per AZ."
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnets for the load balancer and NAT gateway, one per AZ."
  type        = list(string)
}

variable "single_nat_gateway" {
  description = "One shared NAT gateway (cheaper) instead of one per AZ (survives an AZ outage)."
  type        = bool
}

# EKS

variable "kubernetes_version" {
  description = "EKS Kubernetes minor version. Patch versions are managed by AWS."
  type        = string
}

variable "admin_principal_arn" {
  description = "IAM principal granted cluster-admin through an EKS access entry."
  type        = string
}

variable "endpoint_public_access_cidrs" {
  description = "CIDRs allowed to reach the public EKS API endpoint. Set in local.auto.tfvars, which is not committed."
  type        = list(string)
}

variable "cluster_log_types" {
  description = "Control plane log types sent to CloudWatch."
  type        = list(string)
}

variable "cluster_log_retention_days" {
  description = "CloudWatch retention for control plane logs."
  type        = number
}

variable "node_ami_type" {
  description = "AMI type of the managed node group."
  type        = string
}

variable "node_instance_types" {
  description = "Instance types for the managed node group."
  type        = list(string)
}

variable "node_min_size" {
  description = "Minimum number of worker nodes."
  type        = number
}

variable "node_max_size" {
  description = "Maximum number of worker nodes."
  type        = number
}

variable "node_desired_size" {
  description = "Initial number of worker nodes."
  type        = number
}

# ECR and CI

variable "ecr_repository_name" {
  description = "ECR repository for the application image."
  type        = string
}

variable "ecr_keep_image_count" {
  description = "Number of most recent images kept in ECR."
  type        = number
}

variable "ecr_untagged_expiry_days" {
  description = "Days after which untagged images are deleted."
  type        = number
}

variable "github_repository" {
  description = "GitHub repository (owner/name) whose main branch may push images to ECR."
  type        = string
}

variable "github_oidc_sub_prefix" {
  description = "Immutable OIDC subject prefix of the repository (GET repos/{repo}/actions/oidc/customization/sub)."
  type        = string
}

variable "endpoint_public_access" {
  description = "Expose the EKS API publicly (restricted to endpoint_public_access_cidrs). False = reachable only from inside the VPC."
  type        = bool
}

variable "node_webhook_ports" {
  description = "Ports on which the control plane may call webhooks running on nodes, by component."
  type        = map(number)
}
