# Monitoring with Elastic

The monitoring design for the platform, and its alert rules as Terraform. The design is
documented, not deployed: the cluster runs no Elastic components. The decision and its
trade-offs are in [ADR 0009](../../docs/decisions/0009-monitoring-with-elastic.md).

## Collection

```
EKS cluster                                                Elastic Cloud
┌────────────────────────────────────────────┐            ┌──────────────────────┐
│ namespace monitoring                       │            │ Fleet                │
│  Elastic Agent DaemonSet (one per node)    │── HTTPS ──▶│ Elasticsearch        │
│   ├─ Kubernetes integration                │            │  metrics-*  logs-*   │
│   │   kubelet, kube-state-metrics,         │            │ Kibana               │
│   │   container logs, events               │            │  alert rules ──▶ Slack│
│   └─ Prometheus integration                │            └──────────────────────┘
│       nodes-api /metrics, Argo CD metrics  │
│  kube-state-metrics Deployment             │
└────────────────────────────────────────────┘
```

| Signal | Source | Lands in |
|---|---|---|
| Node and pod CPU, memory, network | Kubernetes integration, kubelet | `metrics-kubernetes.*` |
| Desired vs available replicas, container states, restarts | Kubernetes integration, kube-state-metrics | `metrics-kubernetes.state_*` |
| Request count, status and latency of nodes-api | Prometheus integration, `/metrics` on port `http` | `metrics-prometheus.*` |
| Argo CD sync and health of every Application | Prometheus integration, `argocd-application-controller-metrics` | `metrics-prometheus.*` |
| Application logs (one JSON object per line) | Kubernetes integration, container logs | `logs-kubernetes.container_logs-*` |

- **Elastic Agent managed by Fleet:** integrations, versions and policies are changed in
  Kibana, without redeploying the DaemonSet. Installed with the `elastic-agent` Helm chart as
  another Argo CD Application in the `monitoring` namespace.
- **Prometheus integration settings:** `use_types: true` and `rate_counters: true`, so a
  counter such as `http_requests_total` also gets a per-second `.rate` field. Pods are found by
  autodiscovery on the `app.kubernetes.io/name: nodes-api` label, in all three environments.
- **Log parsing:** a `decode_json_fields` processor with `target: nodes_api` turns the app's
  JSON lines into fields (`nodes_api.status`, `nodes_api.path`, `nodes_api.duration_ms`). No
  regular expressions are needed.
- **Network access:** the nodes-api NetworkPolicy already allows ingress from the
  `monitoring` namespace. The scraping agent must run with `hostNetwork: false`. With host
  networking its traffic comes from the node IP, which the namespace rule does not match.
- **Credentials:** the agent's Fleet enrollment token comes from Secrets Manager through
  External Secrets, like the API key ([ADR 0007](../../docs/decisions/0007-secrets-with-external-secrets.md)).

## What is measured

The four golden signals for the service, plus the platform that runs it:

| Signal | Measured by |
|---|---|
| Traffic | `http_requests_total` rate, per environment and route |
| Errors | Share of 5xx in `http_requests_total`; `k8s_api_errors_total` |
| Latency | `duration_ms` in request logs; `http_request_duration_seconds` histogram |
| Saturation | Pod CPU and memory against requests and limits; HPA current vs max replicas; node count against the Cluster Autoscaler maximum |
| Availability | Available vs desired replicas; container restarts and CrashLoopBackOff |
| Delivery | Argo CD sync and health status of each Application |

## Alerts

Five Kibana custom threshold rules in [main.tf](main.tf). Each rule checks every minute,
groups by environment (or Deployment, pod, Application), and sends one Slack message when an
alert starts and one when it recovers.

| Rule | Condition | Severity | First steps |
|---|---|---|---|
| `nodes-api-error-ratio` | 5xx responses above 5% of requests over 5 minutes | critical | Check the app logs for `listing nodes failed`; a 502 means the Kubernetes API call failed (RBAC, NetworkPolicy egress, API server) |
| `nodes-api-latency-p95` | p95 latency of `/nodes` above 500 ms over 10 minutes | warning | Compare with pod CPU throttling and the HPA; check Kubernetes API latency |
| `deployment-replicas-unavailable` | Available replicas below desired for 10 minutes | critical | `kubectl describe` the pods: failed readiness, Pending (no capacity, quota), image pull |
| `pod-crashlooping` | A container in CrashLoopBackOff | critical | `kubectl logs --previous`; check the last Argo CD sync and the Secret from External Secrets |
| `argocd-app-unhealthy` | An Argo CD Application not Healthy or not Synced for 15 minutes | warning | Open the Application in Argo CD: failed sync, policy rejection, or drift that self-heal cannot fix |

Rules that would be added next: HPA at its maximum replicas for 15 minutes (saturation before
errors), node NotReady, and nodes at the Cluster Autoscaler maximum with pods Pending.

## Applying the rules

Requires an Elastic Cloud deployment with Fleet, the integrations above, and a Kibana API
key with the Alerting and Data Views privileges.

```bash
cd monitoring/elastic
cp local.auto.tfvars.example local.auto.tfvars   # git-ignored; set kibana_url
export TF_VAR_kibana_api_key=...                 # never written to a file
export TF_VAR_slack_webhook_url=...              # write-only: not stored in Terraform state
terraform init
terraform plan
terraform apply
```

The Slack webhook is a write-only argument (`secrets_wo`), so it never reaches the state file.
To rotate it, change the webhook and increase `secrets_wo_version`.

CI runs `terraform fmt`, `init` and `validate` on this directory. `plan` and `apply` need a
Kibana and are run manually.
