# 0009. Monitoring with Elastic, documented and not deployed

- Status: accepted
- Date: 2026-10-31

## Context

The assignment asks for a documented monitoring approach with at least three alerts, using
Elastic. The service already exposes Prometheus metrics on `/metrics` and writes one JSON
object per log line. Argo CD exposes Prometheus metrics too.

The cluster runs on two or three small nodes, limited by an 8 vCPU quota. Running
Elasticsearch and Kibana inside it (ECK) would need more memory than the nodes have, and
would mean the monitoring system fails together with the cluster it watches.

## Decision

- **Elastic Cloud** for Elasticsearch, Kibana and Fleet, outside the cluster.
- **Elastic Agent** as a DaemonSet managed by Fleet, with the Kubernetes integration (kubelet,
  kube-state-metrics, container logs) and the Prometheus integration (nodes-api and Argo CD
  metrics). One agent collects metrics and logs.
- **Alerts as code:** five Kibana custom threshold rules, the data views they query and the
  Slack connector, in Terraform with the `elastic/elasticstack` provider
  ([monitoring/elastic](../../monitoring/elastic/)). Rules are reviewed in a PR like any other
  change.
- **Documented, not deployed:** CI validates the Terraform, but nothing is applied and no
  agent runs in the cluster. The design and the rules are the deliverable.

## Alternatives

- **kube-prometheus-stack (Prometheus, Alertmanager, Grafana):** the most common choice for
  Kubernetes metrics, and the app already speaks Prometheus. Not chosen because the
  assignment names Elastic, and logs would need a second system (Loki).
- **ECK in the cluster:** keeps everything in GitOps, but needs several GB of memory for
  Elasticsearch and loses monitoring exactly when the cluster is in trouble.
- **CloudWatch Container Insights:** no extra components, but alert rules and dashboards
  would be AWS-specific, and the assignment names Elastic.

## Consequences

- Metrics and logs are searched in one place, and an alert can link straight to the logs of
  the failing pod.
- The rules are validated by CI but never run, so a field name that differs in a real
  deployment would only show up after `apply`. The field names follow the integrations'
  documented schemas and the app's own metric and log names.
- Elastic Cloud is a paid external dependency, and the agent sends data out of the VPC.

## Production differences

- Apply the rules from CI with a scoped Kibana API key, after review, like the infrastructure.
- Route critical alerts to an on-call tool (PagerDuty, Opsgenie) and warnings to Slack.
- SLOs (availability and latency of `/nodes`) with burn-rate alerts instead of fixed
  thresholds.
- Elastic Cloud reached through AWS PrivateLink, and index lifecycle policies for retention.
- Rules in an Elastic space per environment, or tagged per environment, with separate
  routing for prod.
