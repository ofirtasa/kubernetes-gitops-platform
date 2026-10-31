# Terraform

Two stacks, applied in order. Both keep their state in the same S3 bucket.

| Stack | Creates | State key |
|---|---|---|
| `bootstrap/` | S3 bucket for Terraform state | `bootstrap/terraform.tfstate` |
| `platform/` | VPC, EKS, ECR, GitHub OIDC role, resource group, Pod Identity roles for add-ons, Secrets Manager secrets, Argo CD | `platform/terraform.tfstate` |

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

## Making changes

CI checks Terraform but never applies it (no AWS write access in CI). A change is applied
from `main`, after review:

1. Change the code or `terraform.tfvars` on a branch and open a PR.
2. Run a plan locally and put its summary in the PR, so the reviewer sees what will change:

   ```bash
   cd platform
   terraform plan
   ```

3. CI runs `fmt`, `validate` and the Trivy IaC scan. Merge after approval.
4. Plan again from `main` and check that it matches the plan in the PR, then apply that plan:

   ```bash
   git checkout main && git pull
   terraform plan -out=platform.tfplan
   terraform apply platform.tfplan
   ```

Saved plans (`*.tfplan`) are git-ignored; delete them after the apply.

## Another AWS account or repository

These values name this AWS account (`404386756450`) or this GitHub repository. Replace them
before the first apply:

| Value | Files |
|---|---|
| State bucket name | `bootstrap/terraform.tfvars`, `bootstrap/backend.hcl`, `platform/backend.hcl` |
| Admin user, GitHub repository and its OIDC subject prefix | `platform/terraform.tfvars` |
| ECR registry | `charts/nodes-api/values.yaml`, `policies/restrict-image-registries.yaml`, `policies/tests/resources.yaml` |
| CI role ARN | `.github/workflows/app.yml` |
| Secrets role ARNs | `argocd/platform/secret-stores/*.yaml` |
| Repository URL | `argocd/bootstrap/*.yaml`, `argocd/platform/*.yaml`, `argocd/apps/nodes-api.yaml` |

The OIDC subject prefix of this repository includes the owner and repository IDs
(`owner@id/repo@id`). Check the new repository's subject format with
`gh api repos/<owner>/<repo>/actions/oidc/customization/sub` before writing the prefix.

## Argo CD

The platform stack installs Argo CD and the root Application. From then on, Argo CD deploys
everything under `argocd/` from Git.

The UI is not exposed to the internet. It is reached through a port-forward, with the local
`admin` user.

1. Sign in to AWS and point `kubectl` at this cluster (see [First-time setup](#first-time-setup)).
2. Read the admin password. Argo CD generates it on first start and keeps it only in the
   cluster:

   ```bash
   kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d
   ```

   ```powershell
   $b64 = kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}'
   [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b64))
   ```

3. Open the tunnel and keep the terminal open:

   ```bash
   kubectl -n argocd port-forward svc/argo-cd-argocd-server 8080:443
   ```

4. Open https://localhost:8080 and sign in as `admin`. The browser warns about the
   certificate, because Argo CD serves a self-signed one.

## Destroy

1. Delete Ingress resources first: load balancers created by the AWS Load Balancer
   Controller are not in Terraform state and would block VPC deletion.
2. `platform/`: `terraform destroy`.
3. `bootstrap/`: the bucket holds this stack's own state, so move it back first.
   Comment out the backend block, run `terraform init -migrate-state`, then `terraform destroy`.
