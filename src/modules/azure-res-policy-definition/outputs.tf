output "resource_id" {
  description = "Resource ID of the policy definition."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Policy definition name."
  value       = azapi_resource.this.name
}

output "display_name" {
  description = "Policy definition display name."
  value       = var.display_name
}

output "resource" {
  description = "The full policy definition resource."
  value       = azapi_resource.this
}
