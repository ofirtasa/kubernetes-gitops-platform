# 0003. EKS platform baseline

- Status: accepted
- Date: 2026-10-30

## Context

The service needs a Kubernetes cluster on AWS that hosts dev, staging and production, within
a small budget, while following production practices wherever cost allows.

## Decision

| Area | Choice | Why |
|---|---|---|
| Region | `eu-north-1` | Full service coverage at lower prices than most EU regions |
| Clusters | One EKS cluster, one namespace per environment | Cost; isolation through namespaces, RBAC, NetworkPolicy and per-environment secrets |
| Network | VPC across 3 AZs; nodes in private subnets; public subnets only for the load balancer and NAT | Nodes have no public IPs and are unreachable from the internet |
| Egress | One NAT gateway | Cost |
| API endpoint | Private for nodes; public only for allow-listed CIDRs | Operators can reach the API without a VPN; nobody else can |
| Cluster access | EKS access entries (`authentication_mode = API`); no implicit admin for the Terraform caller | Access is explicit, in code and auditable; no `aws-auth` ConfigMap |
| Workload AWS access | EKS Pod Identity | Simpler than IRSA: no OIDC provider per cluster, no role-trust edits per service account |
| Pod networking | VPC CNI with prefix delegation | Raises pods per node from 17 to 110 on `t3.medium` |
| Nodes | Managed node group, 3 × `t3.medium`, Amazon Linux 2023 | One node per AZ, so PDBs and topology spread are meaningful |
| Node hardening | IMDSv2 required, hop limit 1 | Pods cannot read the node instance role credentials |
| Secrets at rest | Kubernetes Secrets envelope-encrypted with a dedicated KMS key | Protects secret values stored in etcd |
| Audit | Control-plane `audit` and `authenticator` logs to CloudWatch, 7-day retention | Who did what in the cluster, at low log volume |
| Registry | ECR, immutable tags, scan on push, lifecycle policy | A tag always means the same image; old images are cleaned up |
| CI access | GitHub OIDC role limited to `main` of this repository and push to one ECR repository | No long-lived AWS keys in GitHub |
| State | S3 backend with native lock file (`use_lockfile`), versioning, encryption, TLS-only policy | No DynamoDB table needed for locking (Terraform ≥ 1.10) |

All tunable values live in `terraform.tfvars`. Security guardrails (immutable tags,
encryption, IMDSv2, blocked public access) stay in code, so they cannot be weakened by a
variable change.

## Trade-offs and production differences

- **Separate clusters and accounts.** Production would run each environment in its own
  cluster, and production in its own AWS account, so a failure or a mistake in dev cannot
  affect production. Here one cluster keeps the cost within budget.
- **NAT per AZ.** With one NAT gateway, losing its AZ stops all outbound traffic. Production
  would run one per AZ.
- **Private-only API endpoint.** Production would disable the public endpoint and reach the
  API over VPN or a bastion.
- **Node autoscaling.** The node group has a fixed size. Production would add Karpenter so
  nodes follow pod demand, including Spot capacity for non-production environments.
- **Destroyable resources.** The state bucket and ECR repository allow `terraform destroy`
  to delete their contents, because this environment is torn down after review. Production
  would protect them.
