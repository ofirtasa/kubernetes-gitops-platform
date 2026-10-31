################################################################################
# Data views: where the rules search
################################################################################

resource "elasticstack_kibana_data_view" "metrics" {
  data_view = {
    id              = "k8s-gitops-metrics"
    name            = "k8s-gitops metrics"
    title           = "metrics-*"
    time_field_name = "@timestamp"
  }
}

resource "elasticstack_kibana_data_view" "logs" {
  data_view = {
    id              = "k8s-gitops-logs"
    name            = "k8s-gitops logs"
    title           = "logs-*"
    time_field_name = "@timestamp"
  }
}

################################################################################
# Notification channel
################################################################################

resource "elasticstack_kibana_action_connector" "slack" {
  name              = "k8s-gitops alerts"
  connector_type_id = ".slack"

  secrets_wo         = jsonencode({ webhookUrl = var.slack_webhook_url })
  secrets_wo_version = 1
}

################################################################################
# Alert rules (Observability custom threshold)
################################################################################

locals {
  namespaces = join(" or ", var.environments)

  rules = {
    # Users get errors: share of 5xx responses, from the app's Prometheus counters.
    nodes-api-error-ratio = {
      severity  = "critical"
      data_view = elasticstack_kibana_data_view.metrics.data_view.id
      query     = "kubernetes.labels.app_kubernetes_io/name : \"nodes-api\" and kubernetes.namespace : (${local.namespaces})"
      group_by  = ["kubernetes.namespace"]
      metrics = [
        { name = "A", aggType = "sum", field = "prometheus.http_requests_total.rate", filter = "prometheus.labels.status : 5*" },
        { name = "B", aggType = "sum", field = "prometheus.http_requests_total.rate" },
      ]
      equation   = "A / B * 100"
      label      = "5xx responses (%)"
      comparator = ">"
      threshold  = [5]
      window     = 5
    }

    # Users wait: 95th percentile of /nodes latency, from the app's JSON request logs.
    nodes-api-latency-p95 = {
      severity  = "warning"
      data_view = elasticstack_kibana_data_view.logs.data_view.id
      query     = "kubernetes.labels.app_kubernetes_io/name : \"nodes-api\" and nodes_api.path : \"/nodes\""
      group_by  = ["kubernetes.namespace"]
      metrics = [
        { name = "A", aggType = "p95", field = "nodes_api.duration_ms" },
      ]
      equation   = "A"
      label      = "p95 latency (ms)"
      comparator = ">"
      threshold  = [500]
      window     = 10
    }

    # Capacity lost: fewer available replicas than desired (failed rollout, failing
    # readiness, pods that cannot be scheduled).
    deployment-replicas-unavailable = {
      severity  = "critical"
      data_view = elasticstack_kibana_data_view.metrics.data_view.id
      query     = "data_stream.dataset : \"kubernetes.state_deployment\" and kubernetes.namespace : (${local.namespaces})"
      group_by  = ["kubernetes.namespace", "kubernetes.deployment.name"]
      metrics = [
        { name = "A", aggType = "min", field = "kubernetes.deployment.replicas.desired" },
        { name = "B", aggType = "min", field = "kubernetes.deployment.replicas.available" },
      ]
      equation   = "A - B"
      label      = "Unavailable replicas"
      comparator = ">"
      threshold  = [0]
      window     = 10
    }

    # A container keeps crashing: a bad image, missing secret or failing liveness probe.
    pod-crashlooping = {
      severity  = "critical"
      data_view = elasticstack_kibana_data_view.metrics.data_view.id
      query     = "data_stream.dataset : \"kubernetes.state_container\" and kubernetes.container.status.reason : \"CrashLoopBackOff\" and kubernetes.namespace : (${local.namespaces})"
      group_by  = ["kubernetes.namespace", "kubernetes.pod.name"]
      metrics = [
        { name = "A", aggType = "count" },
      ]
      equation   = "A"
      label      = "CrashLoopBackOff samples"
      comparator = ">"
      threshold  = [0]
      window     = 5
    }

    # GitOps broken: an Argo CD Application stays unhealthy or out of sync, so Git no
    # longer describes what runs.
    argocd-app-unhealthy = {
      severity  = "warning"
      data_view = elasticstack_kibana_data_view.metrics.data_view.id
      query     = "prometheus.argocd_app_info.value : * and (not prometheus.labels.health_status : \"Healthy\" or not prometheus.labels.sync_status : \"Synced\")"
      group_by  = ["prometheus.labels.name"]
      metrics = [
        { name = "A", aggType = "count" },
      ]
      equation   = "A"
      label      = "Unhealthy or OutOfSync samples"
      comparator = ">"
      threshold  = [0]
      window     = 15
    }
  }
}

resource "elasticstack_kibana_alerting_rule" "this" {
  for_each = local.rules

  name         = each.key
  consumer     = "observability"
  rule_type_id = "observability.rules.custom_threshold"
  interval     = "1m"
  tags         = ["k8s-gitops", each.value.severity]

  params = jsonencode({
    criteria = [{
      metrics    = each.value.metrics
      equation   = each.value.equation
      label      = each.value.label
      comparator = each.value.comparator
      threshold  = each.value.threshold
      timeSize   = each.value.window
      timeUnit   = "m"
    }]
    groupBy               = each.value.group_by
    alertOnNoData         = false
    alertOnGroupDisappear = false
    searchConfiguration = {
      index = each.value.data_view
      query = { query = each.value.query, language = "kuery" }
    }
  })

  actions {
    id    = elasticstack_kibana_action_connector.slack.connector_id
    group = "custom_threshold.fired"
    params = jsonencode({
      message = "[${upper(each.value.severity)}] {{rule.name}} {{context.group}}: {{context.reason}}\n{{context.viewInAppUrl}}"
    })
    frequency {
      summary     = false
      notify_when = "onActionGroupChange"
    }
  }

  actions {
    id    = elasticstack_kibana_action_connector.slack.connector_id
    group = "recovered"
    params = jsonencode({
      message = "[RESOLVED] {{rule.name}} {{context.group}}"
    })
    frequency {
      summary     = false
      notify_when = "onActionGroupChange"
    }
  }
}
