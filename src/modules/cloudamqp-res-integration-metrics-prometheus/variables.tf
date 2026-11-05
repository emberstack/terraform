variable "instance_id" {
  description = "Identifier of the instance whose metrics are shipped — the `id` output of `cloudamqp-res-instance`."
  type        = string

  validation {
    condition     = can(regex("^[0-9]+$", var.instance_id))
    error_message = "instance_id must be a numeric CloudAMQP instance identifier."
  }
}

variable "metrics_filter" {
  description = "Metric names to ship, for example `rabbitmq_detailed_queue_messages`. Null ships CloudAMQP's default metric set."
  type        = list(string)
  default     = null

  validation {
    condition     = var.metrics_filter == null || length(coalesce(var.metrics_filter, [])) > 0
    error_message = "metrics_filter must not be empty. Use null for CloudAMQP's default metric set."
  }

  validation {
    condition     = var.metrics_filter == null || alltrue([for m in coalesce(var.metrics_filter, []) : length(trimspace(m)) > 0])
    error_message = "metrics_filter entries must not be empty."
  }

  validation {
    condition     = var.metrics_filter == null || length(distinct(coalesce(var.metrics_filter, []))) == length(coalesce(var.metrics_filter, []))
    error_message = "metrics_filter entries must be unique."
  }
}

variable "tags" {
  description = "Tags attached to every shipped metric, rendered for the backend as `key=value,key2=value2`. Azure Monitor takes no tags."
  type        = map(string)
  default     = {}
  nullable    = false

  validation {
    condition = alltrue([
      for k, v in var.tags : length(trimspace(k)) > 0 && length(trimspace(v)) > 0 && !can(regex("[,=]", "${k}${v}"))
    ])
    error_message = "Tag keys and values must not be empty, and must not contain ',' or '='."
  }

  validation {
    condition     = length(var.tags) == 0 || var.azure_monitor == null
    error_message = "The Azure Monitor backend takes no tags. Leave tags empty."
  }
}

# =============================================================================
# BACKENDS — set exactly one
# =============================================================================

variable "azure_monitor" {
  description = <<-EOT
    The Azure Monitor backend. Metrics land in the Application Insights resource
    the connection string points at, and through it in that resource's Log
    Analytics workspace.

    - `connection_string` — the Application Insights connection string.
  EOT
  type = object({
    connection_string = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.azure_monitor == null || can(regex("(?i)(^|;)\\s*InstrumentationKey=[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\s*(;|$)", var.azure_monitor.connection_string))
    error_message = "azure_monitor.connection_string must be an Application Insights connection string with an InstrumentationKey."
  }

  validation {
    condition     = var.azure_monitor == null || try(length(var.azure_monitor.connection_string) <= 4096, false)
    error_message = "azure_monitor.connection_string must be at most 4096 characters."
  }
}

variable "cloudwatch_v3" {
  description = <<-EOT
    The Amazon CloudWatch backend.

    - `iam_role` — ARN of an IAM role allowed `cloudwatch:PutMetricData`.
    - `iam_external_id` — the external ID the role's trust policy expects.
    - `region` — AWS region to publish to, for example `eu-west-1`.
  EOT
  type = object({
    iam_role        = string
    iam_external_id = string
    region          = string
  })
  default = null

  validation {
    condition     = var.cloudwatch_v3 == null || can(regex("^arn:aws[a-z-]*:iam::[0-9]{12}:role/.+$", var.cloudwatch_v3.iam_role))
    error_message = "cloudwatch_v3.iam_role must be an IAM role ARN, for example arn:aws:iam::123456789012:role/example."
  }

  validation {
    condition     = var.cloudwatch_v3 == null || try(length(trimspace(var.cloudwatch_v3.iam_external_id)) > 0, false)
    error_message = "cloudwatch_v3.iam_external_id must not be empty."
  }

  validation {
    condition     = var.cloudwatch_v3 == null || can(regex("^[a-z]{2}(-[a-z]+)+-[0-9]+$", var.cloudwatch_v3.region))
    error_message = "cloudwatch_v3.region must be an AWS region, for example eu-west-1."
  }
}

variable "datadog_v3" {
  description = <<-EOT
    The Datadog backend.

    - `api_key` — Datadog API key.
    - `region` — Datadog site: `us1`, `us3`, `us5`, `eu1` or `ap2`.
    - `rabbitmq_dashboard_metrics_format` — rename metrics to match Datadog's RabbitMQ
      dashboard. RabbitMQ instances only, not LavinMQ. Null takes the provider default (off).
  EOT
  type = object({
    api_key                           = string
    region                            = string
    rabbitmq_dashboard_metrics_format = optional(bool)
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.datadog_v3 == null || try(length(trimspace(var.datadog_v3.api_key)) > 0, false)
    error_message = "datadog_v3.api_key must not be empty."
  }

  validation {
    condition     = var.datadog_v3 == null || try(contains(["us1", "us3", "us5", "eu1", "ap2"], var.datadog_v3.region), false)
    error_message = "datadog_v3.region must be one of us1, us3, us5, eu1 or ap2."
  }
}

variable "dynatrace" {
  description = <<-EOT
    The Dynatrace backend.

    - `environment_id` — Dynatrace environment ID.
    - `access_token` — access token with the 'Ingest metrics' permission.
  EOT
  type = object({
    environment_id = string
    access_token   = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.dynatrace == null || try(length(trimspace(var.dynatrace.environment_id)) > 0 && length(trimspace(var.dynatrace.access_token)) > 0, false)
    error_message = "dynatrace.environment_id and dynatrace.access_token must not be empty."
  }
}

variable "grafana" {
  description = <<-EOT
    The Grafana Cloud (Mimir) backend.

    - `endpoint` — the stack's Prometheus remote write URL, over HTTPS.
    - `instance_id` — the numeric Prometheus instance ID, used as the basic auth username.
      Not the Loki instance ID.
    - `api_token` — token with the `metrics:write` scope, or a service account token
      with the `MetricsPublisher` role.
  EOT
  type = object({
    endpoint    = string
    instance_id = string
    api_token   = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.grafana == null || can(regex("^https://\\S+$", var.grafana.endpoint))
    error_message = "grafana.endpoint must be an https:// URL."
  }

  validation {
    condition     = var.grafana == null || can(regex("^[0-9]+$", var.grafana.instance_id))
    error_message = "grafana.instance_id must be the numeric Prometheus instance ID."
  }

  validation {
    condition     = var.grafana == null || try(length(trimspace(var.grafana.api_token)) > 0, false)
    error_message = "grafana.api_token must not be empty."
  }
}

variable "newrelic_v3" {
  description = <<-EOT
    The New Relic backend.

    - `api_key` — New Relic API key.
    - `region` — `eu` or `us`.
  EOT
  type = object({
    api_key = string
    region  = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.newrelic_v3 == null || try(length(trimspace(var.newrelic_v3.api_key)) > 0, false)
    error_message = "newrelic_v3.api_key must not be empty."
  }

  validation {
    condition     = var.newrelic_v3 == null || try(contains(["eu", "us"], var.newrelic_v3.region), false)
    error_message = "newrelic_v3.region must be eu or us."
  }
}

variable "prometheus_remote_write" {
  description = <<-EOT
    A generic Prometheus remote write receiver — Mimir, Cortex, Thanos, or Azure Monitor
    managed Prometheus behind `oauth2`.

    - `endpoint` — remote write URL including the path, over HTTPS.
    - `auth_type` — `none`, `basic_auth`, `headers` or `oauth2`. Null takes the provider
      default (`none`).
    - `username`, `password` — used with `basic_auth`.
    - `headers` — sent with every request whatever `auth_type` is, one `key: value` pair
      per line. Required with `headers`.
    - `client_id`, `client_secret`, `token_url` — required with `oauth2`; `token_url` is
      over HTTPS.
    - `scopes` — requested with the OAuth2 token, space or comma separated.
  EOT
  type = object({
    endpoint      = string
    auth_type     = optional(string)
    username      = optional(string)
    password      = optional(string)
    headers       = optional(string)
    client_id     = optional(string)
    client_secret = optional(string)
    token_url     = optional(string)
    scopes        = optional(string)
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.prometheus_remote_write == null || can(regex("^https://\\S+$", var.prometheus_remote_write.endpoint))
    error_message = "prometheus_remote_write.endpoint must be an https:// URL."
  }

  validation {
    condition     = var.prometheus_remote_write == null || try(var.prometheus_remote_write.auth_type == null || contains(["none", "basic_auth", "headers", "oauth2"], var.prometheus_remote_write.auth_type), false)
    error_message = "prometheus_remote_write.auth_type must be one of none, basic_auth, headers or oauth2."
  }

  validation {
    condition = var.prometheus_remote_write == null || try(
      var.prometheus_remote_write.auth_type != "headers" || length(trimspace(coalesce(var.prometheus_remote_write.headers, ""))) > 0,
      false
    )
    error_message = "prometheus_remote_write.headers is required when auth_type is headers."
  }

  validation {
    condition = var.prometheus_remote_write == null || try(alltrue([
      for line in split("\n", coalesce(var.prometheus_remote_write.headers, "")) :
      can(regex("^\\s*[^:\\s]+:\\s*\\S", line)) if length(trimspace(line)) > 0
    ]), false)
    error_message = "prometheus_remote_write.headers must hold one 'key: value' pair per line."
  }

  validation {
    condition = var.prometheus_remote_write == null || try(
      var.prometheus_remote_write.auth_type != "oauth2" || alltrue([
        for v in [var.prometheus_remote_write.client_id, var.prometheus_remote_write.client_secret, var.prometheus_remote_write.token_url] :
        length(trimspace(coalesce(v, ""))) > 0
      ]),
      false
    )
    error_message = "prometheus_remote_write.client_id, client_secret and token_url are required when auth_type is oauth2."
  }

  validation {
    condition     = var.prometheus_remote_write == null || try(var.prometheus_remote_write.token_url == null || can(regex("^https://\\S+$", var.prometheus_remote_write.token_url)), false)
    error_message = "prometheus_remote_write.token_url must be an https:// URL."
  }
}

variable "splunk_v2" {
  description = <<-EOT
    The Splunk backend, through the HTTP Event Collector.

    - `endpoint` — HEC URL, for example `https://splunk.example.com:8088/services/collector`.
    - `token` — HEC token.
  EOT
  type = object({
    endpoint = string
    token    = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.splunk_v2 == null || can(regex("^https?://\\S+$", var.splunk_v2.endpoint))
    error_message = "splunk_v2.endpoint must be an http:// or https:// URL."
  }

  validation {
    condition     = var.splunk_v2 == null || try(length(trimspace(var.splunk_v2.token)) > 0, false)
    error_message = "splunk_v2.token must not be empty."
  }
}

variable "stackdriver_v2" {
  description = <<-EOT
    The Google Cloud Monitoring (Stackdriver) backend.

    - `credentials_file` — a service account key JSON file with the 'Monitoring Metric
      Writer' role, Base64-encoded. The provider derives the project and client email
      from it.
  EOT
  type = object({
    credentials_file = string
  })
  default   = null
  sensitive = true

  validation {
    condition     = var.stackdriver_v2 == null || can(jsondecode(base64decode(var.stackdriver_v2.credentials_file)))
    error_message = "stackdriver_v2.credentials_file must be a Base64-encoded JSON service account key."
  }
}
