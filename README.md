# Kubernetes GitOps Platform

A reference implementation of a cloud-native delivery model on AWS: a small Python service
(`nodes-api`) deployed to Amazon EKS through Argo CD, with CI/CD, least-privilege RBAC,
external secrets, policy-as-code and a documented production design.

> Status: work in progress. Deployment instructions are added as each part lands.

## Access

| What | How |
|---|---|
| nodes-api | One ALB for all environments: prod on port 80, dev on 8080, staging on 8081 ([ADR 0006](docs/decisions/0006-ingress-shared-alb.md)). `/nodes` needs the `X-API-Key` header ([ADR 0007](docs/decisions/0007-secrets-with-external-secrets.md)) |
| Argo CD UI | Port-forward with the local `admin` user, see [Terraform README](infra/terraform/README.md#argo-cd) |

## Repository layout

```
├── app/                    # nodes-api source (FastAPI), tests, Dockerfile
├── charts/nodes-api/       # Helm chart for the service
├── environments/           # Helm values: common (cluster-wide) + dev, staging, prod
├── argocd/
│   ├── bootstrap/          # root Application (app of apps)
│   ├── platform/           # cluster add-ons and namespaces
│   └── apps/               # ApplicationSet: nodes-api × 3 environments
├── infra/terraform/
│   ├── bootstrap/          # Terraform state bucket
│   └── platform/           # VPC, EKS, ECR, CI role; later IAM for add-ons and Argo CD
├── policies/               # Kyverno cluster policies
├── monitoring/elastic/     # alert rules as code
├── docs/                   # architecture, production design, operations
│   └── decisions/          # Architecture Decision Records (ADRs)
├── .github/workflows/      # CI and environment promotion
└── .kube-linter.yaml       # static checks for rendered manifests
```

## Design decisions

Each significant decision is recorded as an ADR in [docs/decisions](docs/decisions/):

| ADR | Decision |
|---|---|
| [0001](docs/decisions/0001-single-repository-layout.md) | Single repository, chart separated from environment values |
| [0002](docs/decisions/0002-argo-cd-for-gitops.md) | Argo CD as the GitOps controller |
| [0003](docs/decisions/0003-eks-platform-baseline.md) | EKS platform baseline: network, access, nodes, registry |
| [0004](docs/decisions/0004-application-and-container-image.md) | Application stack and container image |
| [0005](docs/decisions/0005-promotion-and-ci-write-back.md) | Promotion between environments and CI write-back to Git |
| [0006](docs/decisions/0006-ingress-shared-alb.md) | Ingress through one shared ALB |
| [0007](docs/decisions/0007-secrets-with-external-secrets.md) | Secrets from AWS Secrets Manager through External Secrets Operator |
