output "resource_id" {
  description = "Resource ID of the policy set definition (initiative)."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Initiative name."
  value       = azapi_resource.this.name
}

output "display_name" {
  description = "Initiative display name."
  value       = var.display_name
}
