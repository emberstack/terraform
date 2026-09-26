output "resource_id" {
  description = "Resource ID of the rule collection group."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the rule collection group."
  value       = azapi_resource.this.name
}

output "priority" {
  description = "Priority of the rule collection group (echoes `var.priority`)."
  value       = var.priority
}
