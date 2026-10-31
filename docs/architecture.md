# Architecture

## Runtime

One EKS cluster in `eu-north-1`, three availability zones. Each environment is a namespace.

```mermaid
flowchart LR
    user([Client]) -->|HTTP :80 prod<br/>:8080 dev, :8081 staging| alb

    subgraph vpc["VPC 10.0.0.0/20 (3 AZs)"]
        subgraph public["Public subnets"]
            alb[ALB<br/>one IngressGroup]
            nat[NAT gateway]
        end
        subgraph private["Private subnets: managed node group, 2-4 nodes"]
            subgraph envs["Namespaces dev / staging / prod"]
                pods[nodes-api pods<br/>HPA, PDB, NetworkPolicy]
                secret[(Secret nodes-api)]
            end
            subgraph platform["Platform add-ons"]
                argocd[Argo CD]
                lbc[AWS Load Balancer<br/>Controller]
                eso[External Secrets<br/>Operator]
                kyverno[Kyverno]
                ca[Cluster Autoscaler]
            end
        end
    end

    cp[EKS control plane<br/>private + allow-listed public endpoint]
    sm[(Secrets Manager<br/>k8s-gitops/env/nodes-api)]
    ecr[(ECR nodes-api<br/>immutable tags)]
    cw[(CloudWatch<br/>audit logs)]

    alb -->|target type ip| pods
    pods -->|list nodes| cp
    lbc -.->|manages| alb
    eso -->|Pod Identity, role per env| sm
    eso -.->|creates| secret
    secret -.->|mounted file| pods
    kyverno -.->|admission| pods
    ca -.->|resizes node group| private
    private -->|pull images| ecr
    cp --> cw
    private --> nat
```

| Layer | What runs there |
|---|---|
| Public subnets | Only the ALB and the NAT gateway. Nodes have no public IPs |
| Private subnets | All nodes and pods. Pod IPs come from the VPC (VPC CNI, prefix delegation) |
| `dev`, `staging`, `prod` | nodes-api: 1-2, 2-3 and 3-6 replicas. PSA `restricted`, default-deny NetworkPolicy |
| Platform namespaces | Argo CD (installed by Terraform), everything else installed by Argo CD |
| AWS services | ECR for images, Secrets Manager for the API keys, CloudWatch for control plane logs, KMS for Secret encryption in etcd |

## Delivery

CI builds and pushes images; it never talks to the cluster. Argo CD pulls every change from Git.

```mermaid
flowchart LR
    dev([Developer]) -->|PR| gh[GitHub main<br/>ruleset: PR + 7 checks]
    gh --> ci[GitHub Actions<br/>test, lint, build, Trivy]
    ci -->|OIDC role, push| ecr[(ECR<br/>tag = commit SHA)]
    ci -->|GitHub App commits tag| devvals[environments/values-dev.yaml]
    devvals --> gh
    pr1([Promotion PR]) -->|copy tag| stg[values-staging.yaml]
    pr2([Promotion PR]) -->|copy tag| prd[values-prod.yaml]
    stg --> gh
    prd --> gh
    gh -->|poll every 3 min| argo[Argo CD in the cluster]
    argo -->|sync dev, staging, prod| k8s[(EKS)]
    k8s -->|pull image| ecr
```

## GitOps structure

Terraform installs Argo CD and one root Application. Everything else comes from `argocd/`.

```mermaid
flowchart TB
    tf[Terraform<br/>helm_release argocd + root Application] --> root[root: argocd/bootstrap]
    root -->|wave -2| projects[AppProjects<br/>platform, nodes-api]
    root -->|wave -1| platformapp[platform: argocd/platform]
    root -->|wave 0| apps[apps: argocd/apps]
    platformapp -->|wave -1| ns[namespaces dev, staging, prod]
    platformapp -->|wave 0| addons[Cluster Autoscaler,<br/>Load Balancer Controller,<br/>External Secrets, Kyverno]
    platformapp -->|wave 1| stores[SecretStores per env,<br/>Kyverno policies]
    apps --> appset[ApplicationSet nodes-api]
    appset --> d[nodes-api-dev]
    appset --> s[nodes-api-staging]
    appset --> p[nodes-api-prod]
```
