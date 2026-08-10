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

output "resource" {
  description = "The full policy set definition resource. One resource covers both management-group and subscription scope, so consumers see the same shape either way."
  value       = azapi_resource.this
}
