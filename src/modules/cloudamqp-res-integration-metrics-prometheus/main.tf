# =============================================================================
# CLOUDAMQP PROMETHEUS METRIC INTEGRATION (cloudamqp_integration_metric_prometheus)
# =============================================================================
# Ships an instance's Prometheus metrics to one external backend. The provider
# takes exactly one backend block per integration, so each backend is its own
# optional input and a precondition demands exactly one. Several backends on
# one instance are several calls of this module.
#
# Most backend inputs carry a credential and are sensitive. Whether one is set
# is not a secret, so the null checks are unwrapped with nonsensitive().
# Without it the mark spreads to everything derived from them, and the
# `backend` output fails with "Output refers to sensitive values".
#
# `tags` is a map here; every backend but Azure Monitor wants the provider's
# `key=value,key2=value2` string, rendered in key order so it never reorders.
#
# `metrics_filter` is optional and computed in the provider: null leaves
# CloudAMQP's default metric set in place, and the state records whatever the
# API returns without a diff.
# =============================================================================

locals {
  backends = {
    azure_monitor           = nonsensitive(var.azure_monitor != null)
    cloudwatch_v3           = var.cloudwatch_v3 != null
    datadog_v3              = nonsensitive(var.datadog_v3 != null)
    dynatrace               = nonsensitive(var.dynatrace != null)
    grafana                 = nonsensitive(var.grafana != null)
    newrelic_v3             = nonsensitive(var.newrelic_v3 != null)
    prometheus_remote_write = nonsensitive(var.prometheus_remote_write != null)
    splunk_v2               = nonsensitive(var.splunk_v2 != null)
    stackdriver_v2          = nonsensitive(var.stackdriver_v2 != null)
  }

  configured_backends = [for name, set in local.backends : name if set]

  tags = length(var.tags) > 0 ? join(",", [for k, v in var.tags : "${k}=${v}"]) : null
}

resource "cloudamqp_integration_metric_prometheus" "this" {
  instance_id    = var.instance_id
  metrics_filter = var.metrics_filter

  dynamic "azure_monitor" {
    for_each = local.backends.azure_monitor ? [var.azure_monitor] : []
    content {
      connection_string = azure_monitor.value.connection_string
    }
  }

  dynamic "cloudwatch_v3" {
    for_each = local.backends.cloudwatch_v3 ? [var.cloudwatch_v3] : []
    content {
      iam_role        = cloudwatch_v3.value.iam_role
      iam_external_id = cloudwatch_v3.value.iam_external_id
      region          = cloudwatch_v3.value.region
      tags            = local.tags
    }
  }

  dynamic "datadog_v3" {
    for_each = local.backends.datadog_v3 ? [var.datadog_v3] : []
    content {
      api_key                           = datadog_v3.value.api_key
      region                            = datadog_v3.value.region
      rabbitmq_dashboard_metrics_format = datadog_v3.value.rabbitmq_dashboard_metrics_format
      tags                              = local.tags
    }
  }

  dynamic "dynatrace" {
    for_each = local.backends.dynatrace ? [var.dynatrace] : []
    content {
      environment_id = dynatrace.value.environment_id
      access_token   = dynatrace.value.access_token
      tags           = local.tags
    }
  }

  dynamic "grafana" {
    for_each = local.backends.grafana ? [var.grafana] : []
    content {
      endpoint    = grafana.value.endpoint
      instance_id = grafana.value.instance_id
      api_token   = grafana.value.api_token
      tags        = local.tags
    }
  }

  dynamic "newrelic_v3" {
    for_each = local.backends.newrelic_v3 ? [var.newrelic_v3] : []
    content {
      api_key = newrelic_v3.value.api_key
      region  = newrelic_v3.value.region
      tags    = local.tags
    }
  }

  dynamic "prometheus_remote_write" {
    for_each = local.backends.prometheus_remote_write ? [var.prometheus_remote_write] : []
    content {
      endpoint      = prometheus_remote_write.value.endpoint
      auth_type     = prometheus_remote_write.value.auth_type
      username      = prometheus_remote_write.value.username
      password      = prometheus_remote_write.value.password
      headers       = prometheus_remote_write.value.headers
      client_id     = prometheus_remote_write.value.client_id
      client_secret = prometheus_remote_write.value.client_secret
      token_url     = prometheus_remote_write.value.token_url
      scopes        = prometheus_remote_write.value.scopes
      tags          = local.tags
    }
  }

  dynamic "splunk_v2" {
    for_each = local.backends.splunk_v2 ? [var.splunk_v2] : []
    content {
      endpoint = splunk_v2.value.endpoint
      token    = splunk_v2.value.token
      tags     = local.tags
    }
  }

  dynamic "stackdriver_v2" {
    for_each = local.backends.stackdriver_v2 ? [var.stackdriver_v2] : []
    content {
      credentials_file = stackdriver_v2.value.credentials_file
      tags             = local.tags
    }
  }

  lifecycle {
    precondition {
      condition     = length(local.configured_backends) == 1
      error_message = "Set exactly one backend: azure_monitor, cloudwatch_v3, datadog_v3, dynatrace, grafana, newrelic_v3, prometheus_remote_write, splunk_v2 or stackdriver_v2."
    }
  }
}
