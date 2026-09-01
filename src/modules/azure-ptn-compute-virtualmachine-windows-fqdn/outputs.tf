output "resource_id" {
  description = "Resource ID of the run command that sets the primary DNS suffix."
  value       = azapi_resource.dns_suffix.id
}

output "name" {
  description = "Name of the run command resource on the VM."
  value       = azapi_resource.dns_suffix.name
}

output "dns_suffix" {
  description = "The primary DNS suffix written in-guest."
  value       = var.dns_suffix
}
