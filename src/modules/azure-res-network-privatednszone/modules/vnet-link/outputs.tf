output "resource_id" {
  description = "ARM resource ID of the virtual network link."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the virtual network link."
  value       = azapi_resource.this.name
}
