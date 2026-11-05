# =============================================================================
# cloudamqp-res-integration-metrics-prometheus tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation or the backend precondition, and the positive runs need a
# resource graph but not an account. Every backend gets a positive run, which
# also proves its sensitive input survives the dynamic block.
# =============================================================================

mock_provider "cloudamqp" {
  mock_resource "cloudamqp_integration_metric_prometheus" {
    defaults = {
      id = "2001"
    }
  }
}

variables {
  instance_id = "1001"
  azure_monitor = {
    connection_string = "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/;LiveEndpoint=https://westeurope.livediagnostics.monitor.azure.com/"
  }
}

# =============================================================================
# POSITIVE — one run per backend; the graph and outputs must evaluate
# =============================================================================

run "plans_azure_monitor" {
  command = plan

  assert {
    condition     = cloudamqp_integration_metric_prometheus.this.instance_id == 1001
    error_message = "instance_id must reach the integration as the instance's identifier."
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.azure_monitor) == 1 && length(cloudamqp_integration_metric_prometheus.this.datadog_v3) == 0
    error_message = "Only the azure_monitor block may be rendered."
  }

  assert {
    condition     = output.backend == "azure_monitor"
    error_message = "The backend output must name the configured backend."
  }
}

run "applies_metrics_filter" {
  command = apply

  variables {
    metrics_filter = [
      "rabbitmq_detailed_queue_messages",
      "rabbitmq_detailed_queue_messages_ready",
      "rabbitmq_detailed_queue_messages_unacked",
    ]
  }

  assert {
    condition     = output.metrics_filter == tolist(["rabbitmq_detailed_queue_messages", "rabbitmq_detailed_queue_messages_ready", "rabbitmq_detailed_queue_messages_unacked"])
    error_message = "metrics_filter must reach the integration in the order given."
  }

  assert {
    condition     = output.id == "2001"
    error_message = "The id output must be the integration identifier."
  }
}

run "plans_cloudwatch_v3_with_tags" {
  command = plan

  variables {
    azure_monitor = null
    cloudwatch_v3 = {
      iam_role        = "arn:aws:iam::123456789012:role/example"
      iam_external_id = "example-external-id"
      region          = "eu-west-1"
    }
    tags = {
      service = "rabbitmq"
      env     = "prod"
    }
  }

  assert {
    condition     = one(cloudamqp_integration_metric_prometheus.this.cloudwatch_v3).tags == "env=prod,service=rabbitmq"
    error_message = "tags must render as key=value pairs in key order."
  }

  assert {
    condition     = output.backend == "cloudwatch_v3"
    error_message = "The backend output must name the configured backend."
  }
}

run "plans_datadog_v3" {
  command = plan

  variables {
    azure_monitor = null
    datadog_v3 = {
      api_key                           = "example-api-key"
      region                            = "eu1"
      rabbitmq_dashboard_metrics_format = true
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.datadog_v3) == 1 && length(cloudamqp_integration_metric_prometheus.this.azure_monitor) == 0
    error_message = "Only the datadog_v3 block may be rendered."
  }

  assert {
    condition     = one(cloudamqp_integration_metric_prometheus.this.datadog_v3).tags == null
    error_message = "Empty tags must reach the backend as null."
  }
}

run "plans_dynatrace" {
  command = plan

  variables {
    azure_monitor = null
    dynatrace = {
      environment_id = "abc12345"
      access_token   = "example-token"
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.dynatrace) == 1
    error_message = "The dynatrace block must be rendered."
  }
}

run "plans_grafana" {
  command = plan

  variables {
    azure_monitor = null
    grafana = {
      endpoint    = "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push"
      instance_id = "123456"
      api_token   = "example-token"
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.grafana) == 1
    error_message = "The grafana block must be rendered."
  }
}

run "plans_newrelic_v3" {
  command = plan

  variables {
    azure_monitor = null
    newrelic_v3 = {
      api_key = "example-api-key"
      region  = "eu"
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.newrelic_v3) == 1
    error_message = "The newrelic_v3 block must be rendered."
  }
}

run "plans_prometheus_remote_write_oauth2" {
  command = plan

  variables {
    azure_monitor = null
    prometheus_remote_write = {
      endpoint      = "https://mimir.example.com/api/v1/push"
      auth_type     = "oauth2"
      client_id     = "00000000-0000-0000-0000-000000000000"
      client_secret = "example-secret"
      token_url     = "https://login.example.com/oauth2/v2.0/token"
      scopes        = "https://monitor.example.com/.default"
      headers       = "X-Scope-OrgID: example-tenant"
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.prometheus_remote_write) == 1
    error_message = "The prometheus_remote_write block must be rendered."
  }
}

run "plans_splunk_v2" {
  command = plan

  variables {
    azure_monitor = null
    splunk_v2 = {
      endpoint = "https://splunk.example.com:8088/services/collector"
      token    = "example-token"
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.splunk_v2) == 1
    error_message = "The splunk_v2 block must be rendered."
  }
}

run "plans_stackdriver_v2" {
  command = plan

  variables {
    azure_monitor = null
    stackdriver_v2 = {
      credentials_file = "eyJ0eXBlIjoic2VydmljZV9hY2NvdW50In0=" # {"type":"service_account"}
    }
  }

  assert {
    condition     = length(cloudamqp_integration_metric_prometheus.this.stackdriver_v2) == 1
    error_message = "The stackdriver_v2 block must be rendered."
  }
}

# =============================================================================
# NEGATIVE — backend selection
# =============================================================================

run "rejects_no_backend" {
  command = plan

  variables {
    azure_monitor = null
  }

  expect_failures = [cloudamqp_integration_metric_prometheus.this]
}

run "rejects_two_backends" {
  command = plan

  variables {
    newrelic_v3 = {
      api_key = "example-api-key"
      region  = "us"
    }
  }

  expect_failures = [cloudamqp_integration_metric_prometheus.this]
}

# =============================================================================
# NEGATIVE — variable validation must reject bad input
# =============================================================================

run "rejects_non_numeric_instance_id" {
  command = plan

  variables {
    instance_id = "rmq-example"
  }

  expect_failures = [var.instance_id]
}

run "rejects_empty_metrics_filter" {
  command = plan

  variables {
    metrics_filter = []
  }

  expect_failures = [var.metrics_filter]
}

run "rejects_duplicate_metrics" {
  command = plan

  variables {
    metrics_filter = ["rabbitmq_detailed_queue_messages", "rabbitmq_detailed_queue_messages"]
  }

  expect_failures = [var.metrics_filter]
}

run "rejects_tags_on_azure_monitor" {
  command = plan

  variables {
    tags = { env = "prod" }
  }

  expect_failures = [var.tags]
}

run "rejects_tag_with_separator" {
  command = plan

  variables {
    azure_monitor = null
    newrelic_v3 = {
      api_key = "example-api-key"
      region  = "eu"
    }
    tags = { env = "prod,service=web" }
  }

  expect_failures = [var.tags]
}

run "rejects_connection_string_without_ikey" {
  command = plan

  variables {
    azure_monitor = {
      connection_string = "IngestionEndpoint=https://westeurope-5.in.applicationinsights.azure.com/"
    }
  }

  expect_failures = [var.azure_monitor]
}

run "rejects_bare_instrumentation_key" {
  command = plan

  variables {
    azure_monitor = {
      connection_string = "00000000-0000-0000-0000-000000000000"
    }
  }

  expect_failures = [var.azure_monitor]
}

run "rejects_bad_iam_role" {
  command = plan

  variables {
    azure_monitor = null
    cloudwatch_v3 = {
      iam_role        = "example-role"
      iam_external_id = "example-external-id"
      region          = "eu-west-1"
    }
  }

  expect_failures = [var.cloudwatch_v3]
}

run "rejects_unknown_datadog_region" {
  command = plan

  variables {
    azure_monitor = null
    datadog_v3 = {
      api_key = "example-api-key"
      region  = "eu"
    }
  }

  expect_failures = [var.datadog_v3]
}

run "rejects_non_numeric_grafana_instance" {
  command = plan

  variables {
    azure_monitor = null
    grafana = {
      endpoint    = "https://prometheus-prod-01-eu-west-0.grafana.net/api/prom/push"
      instance_id = "stack-example"
      api_token   = "example-token"
    }
  }

  expect_failures = [var.grafana]
}

run "rejects_unknown_newrelic_region" {
  command = plan

  variables {
    azure_monitor = null
    newrelic_v3 = {
      api_key = "example-api-key"
      region  = "eu1"
    }
  }

  expect_failures = [var.newrelic_v3]
}

run "rejects_http_remote_write_endpoint" {
  command = plan

  variables {
    azure_monitor = null
    prometheus_remote_write = {
      endpoint = "http://mimir.example.com/api/v1/push"
    }
  }

  expect_failures = [var.prometheus_remote_write]
}

run "rejects_oauth2_without_secret" {
  command = plan

  variables {
    azure_monitor = null
    prometheus_remote_write = {
      endpoint  = "https://mimir.example.com/api/v1/push"
      auth_type = "oauth2"
      client_id = "00000000-0000-0000-0000-000000000000"
      token_url = "https://login.example.com/oauth2/v2.0/token"
    }
  }

  expect_failures = [var.prometheus_remote_write]
}

run "rejects_headers_auth_without_headers" {
  command = plan

  variables {
    azure_monitor = null
    prometheus_remote_write = {
      endpoint  = "https://mimir.example.com/api/v1/push"
      auth_type = "headers"
    }
  }

  expect_failures = [var.prometheus_remote_write]
}

run "rejects_malformed_header" {
  command = plan

  variables {
    azure_monitor = null
    prometheus_remote_write = {
      endpoint = "https://mimir.example.com/api/v1/push"
      headers  = "Authorization Bearer example"
    }
  }

  expect_failures = [var.prometheus_remote_write]
}

run "rejects_non_base64_credentials" {
  command = plan

  variables {
    azure_monitor = null
    stackdriver_v2 = {
      credentials_file = "{\"type\":\"service_account\"}"
    }
  }

  expect_failures = [var.stackdriver_v2]
}
