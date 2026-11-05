output "id" {
  description = "The integration identifier."
  value       = cloudamqp_integration_metric_prometheus.this.id
}

output "backend" {
  description = "Name of the configured backend — the input that was set, for example `azure_monitor`."
  value       = length(local.configured_backends) == 1 ? local.configured_backends[0] : null
}

output "metrics_filter" {
  description = "Metric names the integration ships — the input when set, otherwise the default set CloudAMQP reports."
  value       = cloudamqp_integration_metric_prometheus.this.metrics_filter
}
