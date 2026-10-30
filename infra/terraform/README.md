# Terraform

Two stacks, applied in order. Both keep their state in the same S3 bucket.

| Stack | Creates | State key |
|---|---|---|
| `bootstrap/` | S3 bucket for Terraform state | `bootstrap/terraform.tfstate` |
| `platform/` | VPC, EKS, ECR, GitHub OIDC role | `platform/terraform.tfstate` |

Design decisions: [ADR 0003](../../docs/decisions/0003-eks-platform-baseline.md).

## Prerequisites

- Terraform ≥ 1.10, AWS CLI ≥ 2.32
- An AWS profile with admin rights, e.g. `aws login --profile k8s-gitops`

```bash
export AWS_PROFILE=k8s-gitops
```

## First-time setup

The bucket must exist before any stack can use it, so `bootstrap/` starts with local state
and moves it into the bucket afterwards.

```bash
cd bootstrap
# Comment out the backend "s3" {} block in versions.tf, then:
terraform init
terraform apply
# Restore the backend block, then move the state into the bucket:
terraform init -migrate-state -backend-config=backend.hcl

cd ../platform
cp local.auto.tfvars.example local.auto.tfvars   # set your public IP
terraform init -backend-config=backend.hcl
terraform plan -out=platform.tfplan
terraform apply platform.tfplan

aws eks update-kubeconfig --region eu-north-1 --name k8s-gitops
```

Afterwards, both stacks only need `terraform init -backend-config=backend.hcl`.

## Destroy

1. Delete Ingress resources first: load balancers created by the AWS Load Balancer
   Controller are not in Terraform state and would block VPC deletion.
2. `platform/`: `terraform destroy`.
3. `bootstrap/`: the bucket holds this stack's own state, so move it back first.
   Comment out the backend block, run `terraform init -migrate-state`, then `terraform destroy`.
