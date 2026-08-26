output "name" {
  description = "Release name."
  value       = helm_release.this.name
}

output "namespace" {
  description = "Namespace the release is installed in."
  value       = helm_release.this.namespace
}

output "chart" {
  description = "Chart name as resolved by Helm, which is the chart's own name rather than the reference that selected it."
  value       = helm_release.this.metadata.chart
}

output "chart_version" {
  description = "Chart version installed. Resolved at apply time, so this is the concrete version even when `chart_version` was left null."
  value       = helm_release.this.metadata.version
}

output "app_version" {
  description = "Version of the application the chart deploys. Tracks separately from the chart version."
  value       = helm_release.this.metadata.app_version
}

output "revision" {
  description = "Release revision number, incremented by every upgrade."
  value       = helm_release.this.metadata.revision
}

output "status" {
  description = "Release status reported by Helm, e.g. `deployed`."
  value       = helm_release.this.status
}

output "notes" {
  description = "Rendered NOTES.txt. Marked sensitive because charts that generate a password commonly print it here."
  value       = helm_release.this.metadata.notes
  sensitive   = true
}
