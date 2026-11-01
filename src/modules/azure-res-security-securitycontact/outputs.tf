output "resource_id" {
  description = "Resource ID of the security contact."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Security contact name — always `default`."
  value       = azapi_resource.this.name
}
