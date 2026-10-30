# Terraform

Two stacks, applied in order:

| Stack | Creates | State |
|---|---|---|
| `bootstrap/` | S3 bucket for Terraform state | Local (the bucket cannot hold the state that creates it) |
| `platform/` | VPC, EKS, ECR, GitHub OIDC role | S3 bucket from `bootstrap/` |

Design decisions: [ADR 0003](../../docs/decisions/0003-eks-platform-baseline.md).

## Prerequisites

- Terraform ≥ 1.10, AWS CLI ≥ 2.32
- An AWS profile with admin rights, e.g. `aws login --profile k8s-gitops`

```bash
export AWS_PROFILE=k8s-gitops
```

## Apply

```bash
cd bootstrap
terraform init
terraform apply

cd ../platform
cp local.auto.tfvars.example local.auto.tfvars   # set your public IP
terraform init -backend-config=backend.hcl
terraform plan -out=platform.tfplan
terraform apply platform.tfplan

aws eks update-kubeconfig --region eu-north-1 --name k8s-gitops
```

## Destroy

Load balancers created by the AWS Load Balancer Controller are not in Terraform state.
Delete Ingress resources first, then destroy `platform/`, then `bootstrap/`.
