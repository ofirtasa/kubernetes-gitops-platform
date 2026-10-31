# Terraform

Two stacks, applied in order. Both keep their state in the same S3 bucket.

| Stack | Creates | State key |
|---|---|---|
| `bootstrap/` | S3 bucket for Terraform state | `bootstrap/terraform.tfstate` |
| `platform/` | VPC, EKS, ECR, GitHub OIDC role, resource group, Pod Identity roles for add-ons, Argo CD | `platform/terraform.tfstate` |

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

aws eks update-kubeconfig --region eu-north-1 --name k8s-gitops \
  --kubeconfig ~/.kube/k8s-gitops --alias k8s-gitops
export KUBECONFIG=~/.kube/k8s-gitops    # PowerShell: $env:KUBECONFIG="$HOME\.kube\k8s-gitops"
```

A separate kubeconfig file keeps this cluster apart from any other clusters in
`~/.kube/config`, so a command meant for one cluster cannot reach another.

Afterwards, both stacks only need `terraform init -backend-config=backend.hcl`.

## Argo CD

The platform stack installs Argo CD and the root Application. From then on, Argo CD deploys
everything under `argocd/` from Git.

```bash
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
# Open https://localhost:8080 and sign in as admin
```

## Destroy

1. Delete Ingress resources first: load balancers created by the AWS Load Balancer
   Controller are not in Terraform state and would block VPC deletion.
2. `platform/`: `terraform destroy`.
3. `bootstrap/`: the bucket holds this stack's own state, so move it back first.
   Comment out the backend block, run `terraform init -migrate-state`, then `terraform destroy`.
