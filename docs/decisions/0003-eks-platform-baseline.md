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
| Network | VPC `10.0.0.0/20` across 3 AZs; private `/22` subnets for nodes and pods; public `/26` subnets only for the load balancer and NAT | Nodes have no public IPs and are unreachable from the internet. Sized from the expected pod count, see below |
| Private AWS access | S3 gateway endpoint | Free; image layers from ECR (stored in S3) bypass the NAT gateway |
| Pod-level segmentation | NetworkPolicy enforced natively by the VPC CNI | No extra CNI; default-deny per namespace with explicit allows |
| Egress | One NAT gateway | Cost |
| API endpoint | Private for nodes; public endpoint open to any address | Operators and the review demo reach the API without a VPN, from networks not known in advance. An IP allow-list broke whenever the operator's address changed. Every request beyond health and version endpoints still needs IAM authentication and an EKS access entry |
| Cluster access | EKS access entries (`authentication_mode = API`); no implicit admin for the Terraform caller | Access is explicit, in code and auditable; no `aws-auth` ConfigMap |
| Workload AWS access | EKS Pod Identity | Simpler than IRSA: no OIDC provider per cluster, no role-trust edits per service account |
| Pod networking | VPC CNI with prefix delegation | Raises the pods-per-node limit to 110 instead of the ENI-based limit |
| Nodes | Managed node group, 2–4 × `c7i-flex.large` (2 vCPU, 4 GiB), Amazon Linux 2023, subnets in all 3 AZs | Starts with one node per AZ, so PDBs and topology spread are meaningful. 4 GiB per node fits the platform add-ons with room for rollouts and HPA. The account is on the AWS Free plan, which only launches Free Tier eligible types: `t3.medium` is rejected and `t3.small` (2 GiB) is too small |
| Node hardening | IMDSv2 required, hop limit 1 | Pods cannot read the node instance role credentials |
| Node security group | Only the ports in use: 443 and 10250 from the control plane, 10251 (metrics-server), 9443 (Kyverno and load balancer controller webhooks), DNS and pod-to-pod between nodes | Least privilege; the module's recommended set also opens 4443, 6443 and 8443 for tools not used here |
| Secrets at rest | Kubernetes Secrets envelope-encrypted with a dedicated KMS key | Protects secret values stored in etcd |
| Audit | Control-plane `audit` and `authenticator` logs to CloudWatch, 7-day retention | Who did what in the cluster, at low log volume |
| Registry | ECR, immutable tags, scan on push, lifecycle policy | A tag always means the same image; old images are cleaned up |
| CI access | GitHub OIDC role limited to `main` of this repository and push to one ECR repository | No long-lived AWS keys in GitHub |
| State | S3 backend with native lock file (`use_lockfile`), versioning, encryption, TLS-only policy | No DynamoDB table needed for locking (Terraform ≥ 1.10) |

## Subnet sizing

Every pod gets a VPC IP. With prefix delegation a node takes IPs in `/28` blocks (16 IPs):

- About 40 pods in total (Argo CD, Kyverno, ESO, load balancer controller, CoreDNS,
  metrics-server, and the service in three environments including HPA growth).
- Per node: about 15 pods = 1 prefix in use + 1 warm prefix (32 IPs) + up to 3 ENI primary
  IPs, so about 35 IPs.
- Worst case per AZ: 2 nodes (scale-out plus a replacement node during an upgrade) = about
  70 IPs.
- A `/22` gives 1,019 usable IPs per AZ: over 10x headroom, which also leaves contiguous
  `/28` blocks free (prefix delegation fails on fragmented subnets). A `/24` (251) would
  work today but leaves little room for node autoscaling.
- Public subnets hold only the load balancer (needs at least 8 free IPs per subnet) and the
  NAT gateway: `/26` (59 usable) is enough.

All tunable values live in `terraform.tfvars`. Security guardrails (immutable tags,
encryption, IMDSv2, blocked public access) stay in code, so they cannot be weakened by a
variable change.

## Trade-offs and production differences

- **Separate clusters and accounts.** Production would run each environment in its own
  cluster, and production in its own AWS account, so a failure or a mistake in dev cannot
  affect production. Here one cluster keeps the cost within budget.
- **NAT per AZ.** With one NAT gateway, losing its AZ stops all outbound traffic. Production
  would run one per AZ.
- **Egress filtering.** The NAT gateway lets pods reach any internet address. Production
  would filter egress by domain (AWS Network Firewall or an egress proxy) and use VPC
  interface endpoints plus ECR pull-through cache so most traffic never leaves AWS.
- **Private-only API endpoint.** Production would disable the public endpoint and reach the
  API over VPN or a bastion. A public endpoint relies on authentication alone, and exposes the
  API server to scanning and to any future vulnerability before authentication. If a public
  endpoint is required, it is limited to the fixed egress IPs of the office VPN and CI.
- **Instance types.** Production would use current general-purpose instances, preferably
  Graviton (`m7g`/`m8g`, about 20% cheaper for the same performance, with multi-arch images),
  chosen by Karpenter per workload, and Spot for non-production environments.
- **Node autoscaling.** Cluster Autoscaler resizes the managed node group between
  `node_min_size` and `node_max_size` (2–4). At low load it removes a node to save cost, and
  adds it back when pods are Pending.
  - It runs v1.36.1, one minor version behind the cluster, because 1.37 is not released yet.
    It should be upgraded when that release comes out.
  - The account's 8 vCPU On-Demand quota caps the cluster at 4 nodes anyway.
  - Node updates use the `MINIMAL` strategy, one node at a time: an old node is terminated
    before its replacement launches. The default strategy launches up to twice as many new
    nodes as there are AZs before it removes old ones, and the quota rejects that. Production
    would keep the default, which never reduces capacity during an update.
  - Production would use Karpenter instead: it picks the instance type per workload, without
    node groups, and adds Spot capacity for non-production environments.
- **Destroyable resources.** The state bucket and ECR repository allow `terraform destroy`
  to delete their contents, because this environment is torn down after review. Production
  would protect them.
