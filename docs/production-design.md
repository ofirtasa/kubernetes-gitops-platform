# Production design (AWS)

How this platform would run for a business-critical service. Each row contrasts what this
repository does with what production would do; the reasons for the current choices are in
the ADRs.

## Cluster architecture

- **One EKS cluster per environment**, and prod in its own AWS account (AWS Organizations,
  separate accounts for prod, non-prod, shared services and security). Here: one cluster,
  one namespace per environment, to stay within budget (ADR 0003).
- Control plane managed by EKS; upgrades one minor version at a time, non-prod first.
- **Karpenter** instead of managed node groups and Cluster Autoscaler: it picks instance types
  per workload, consolidates under-used nodes, and uses Spot for non-prod. Graviton instances
  with multi-arch images.
- Platform add-ons (Argo CD, Kyverno, ESO, load balancer controller) on a small dedicated
  node pool with a taint, so application load cannot starve them.

## Networking

- VPC per environment, three AZs, private subnets for nodes and pods, public subnets only for
  load balancers. **One NAT gateway per AZ** (here: one).
- **Private API endpoint only**, reached over VPN or AWS Client VPN. Here: public endpoint
  limited to allow-listed IPs.
- VPC interface endpoints (ECR, STS, Secrets Manager, CloudWatch) and ECR pull-through cache,
  so most AWS traffic never reaches the NAT.
- Egress filtering by domain with AWS Network Firewall.
- NetworkPolicy default-deny per namespace, as implemented here.

## Ingress, DNS and TLS

- A domain in **Route 53**, one host per environment (`api.example.com`,
  `api.dev.example.com`), managed from the Ingress objects by **ExternalDNS**.
- **ACM certificates** on the ALB, HTTPS only, HTTP redirected; TLS 1.2+ policy.
- **AWS WAF** with managed rule sets and rate limiting; ALB access logs to S3.
- A separate ALB per cluster. Here: one shared ALB, one listener port per environment, plain
  HTTP, because there is no domain (ADR 0006).

## IAM and workload identity

- People: IAM Identity Center with SSO and MFA, mapped to EKS access entries with read-only,
  developer and admin roles per account. Break-glass admin with alerting on use.
- Workloads: **EKS Pod Identity**, one role per service account with least-privilege
  policies, as implemented here.
- CI: GitHub OIDC roles scoped to a branch and an action, as implemented here. A separate
  role for Terraform `plan` on PRs and `apply` after approval.
- Kubernetes RBAC: least privilege per service (here: `list` on `nodes` only), no
  cluster-admin for applications.

## Container registry

- ECR with immutable tags, scan on push and lifecycle rules, as implemented here.
- **Image signing** in CI (Cosign or AWS Signer) and a Kyverno policy that admits only signed
  images.
- Cross-region replication for DR; one shared registry account that the environment accounts
  pull from.

## Secrets management

- Secrets Manager + External Secrets Operator with a role per environment, as implemented
  here (ADR 0007).
- A customer managed KMS key per environment; automatic rotation with rotation Lambdas.
- In separate accounts, each environment has its own Secrets Manager, so separation is
  enforced by the account boundary.

## Environment separation

| | Here | Production |
|---|---|---|
| Compute | Namespaces in one cluster | One cluster per environment |
| AWS | One account | Account per environment (at least prod vs non-prod) |
| Network | NetworkPolicy | Separate VPCs; no route between prod and non-prod |
| Access | AppProjects, RBAC, per-env secret roles | Same, plus account-level SCPs |
| Delivery | One Argo CD, promotion by PR | Argo CD per cluster or hub-and-spoke; same PR promotion |

## Audit logging

- EKS control plane `audit` and `authenticator` logs (enabled here, 7 days) shipped to a
  central log account, retained for a year or as compliance requires.
- **CloudTrail** organization trail to an S3 bucket with Object Lock; GuardDuty with EKS
  protection; AWS Config rules.
- Git history and Argo CD sync history record every deployment and who approved it.

## Encryption

- In transit: TLS at the ALB; TLS between the ALB and pods, or a service mesh with mTLS, if
  the data requires it.
- At rest: Kubernetes Secrets envelope-encrypted with KMS (implemented here); EBS, S3, ECR and
  Secrets Manager encrypted with customer managed keys.

## Backup and restore

- The cluster is rebuilt from Git and Terraform, not backed up as a whole: Terraform creates
  the infrastructure, Argo CD re-creates every workload.
- **Velero** backs up what Git does not hold: persistent volumes (EBS snapshots) and any
  manually created objects, to S3 in another region.
- Terraform state bucket: versioning (implemented here), replication and deletion protection.
- Restore is tested on a schedule by building a cluster from scratch.

## Scaling and node provisioning

- Pods: HPA on CPU (implemented here); on request rate or latency with KEDA or the Prometheus
  adapter for a more accurate signal.
- Nodes: Karpenter, with Spot for non-prod and On-Demand plus Savings Plans for prod.
- Capacity: PDBs and topology spread across AZs (implemented here); prod runs at least three
  replicas, one per AZ.
- Service quotas monitored and raised ahead of need (this project hit the 8 vCPU limit).

## Cost

- Biggest fixed costs: EKS control plane per cluster, NAT gateways, load balancers. Shared
  non-prod clusters and VPC endpoints reduce them.
- Right-size requests from real usage (Kubecost or the Elastic metrics), Spot for non-prod,
  Savings Plans for the steady prod baseline, Graviton for price-performance.
- Tags on every resource for cost allocation (here: `Project`, with a resource group), an
  `Environment` tag per account, and AWS Budgets alerts.

## Disaster recovery

- **Multi-AZ** by default: nodes, replicas and the ALB span three AZs, so one AZ can fail.
- **Region failure:** a warm standby cluster in a second region, built by the same Terraform
  and synced by Argo CD from the same Git repository; ECR replication and Secrets Manager
  replica secrets; Route 53 health checks fail traffic over.
- Targets agreed with the business, for example RTO 1 hour and RPO 15 minutes. The service
  here is stateless, so its RPO is zero; a stateful service would add database replication.
- DR is rehearsed, not only documented.
