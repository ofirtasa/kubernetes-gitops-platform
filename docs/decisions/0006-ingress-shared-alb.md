# 0006. Ingress through one shared ALB

- Status: accepted
- Date: 2026-10-31

## Context

Each environment of nodes-api must be reachable from outside the cluster. There is no domain,
so there are no DNS names or TLS certificates, and every additional load balancer costs about
$18 a month.

## Decision

- **AWS Load Balancer Controller** turns each Ingress into ALB configuration. Argo CD deploys
  it, and its AWS permissions come from a Pod Identity role created by Terraform.
- **One ALB for all environments:** the three Ingresses share the IngressGroup `k8s-gitops`.
  - Without a domain, there is no host-based routing, so each environment gets its own
    listener port on the ALB DNS name:

    | Environment | URL |
    |---|---|
    | prod | `http://<alb-dns>/` |
    | dev | `http://<alb-dns>:8080/` |
    | staging | `http://<alb-dns>:8081/` |

- **Target type `ip`:** the ALB sends traffic straight to pod IPs, which the VPC CNI makes
  routable. There is no extra hop through a NodePort, and the NetworkPolicy allows the public
  subnets (where the ALB runs) to reach the pods.
- **Health check on `/ready`:** a pod that cannot reach the Kubernetes API stops getting
  traffic. `/health` stays the liveness probe.
- **Pod readiness gates:** the environment namespaces carry
  `elbv2.k8s.aws/pod-readiness-gate-inject: enabled`. A new pod is Ready only once the ALB
  reports it healthy, so a rolling update never removes the last healthy target.
- **Controller settings:**
  - 2 replicas with a PDB.
  - The Service mutating webhook is disabled, because no Service of type LoadBalancer is used.
  - AWS resources it creates are tagged `Project=k8s-gitops`, so they show up in the
    project's resource group.

## Consequences

- One ALB to pay for and one DNS name to share during the review.
- A change to one environment's Ingress updates the shared ALB. A broken Ingress in dev can
  block changes to the group, but not the traffic already being served.
- The ALB is created by the controller, not by Terraform. Ingresses must be deleted before
  `terraform destroy`, otherwise the ALB keeps the VPC from being deleted (see the Terraform
  README).
- Traffic is plain HTTP.

## Production differences

- A domain in Route 53 with host-based routing (`dev.example.com`, `api.example.com`), and an
  ACM certificate for HTTPS with redirect from HTTP.
- A separate ALB for production, or a separate cluster altogether (see ADR 0003), so a
  non-production change cannot touch production routing.
- AWS WAF in front of the ALB, and access logs to S3.
- ExternalDNS to manage the DNS records from the Ingress objects.
