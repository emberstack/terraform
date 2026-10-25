output "resource_id" {
  description = "Resource ID of the metric alert rule."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the metric alert rule."
  value       = azapi_resource.this.name
}
