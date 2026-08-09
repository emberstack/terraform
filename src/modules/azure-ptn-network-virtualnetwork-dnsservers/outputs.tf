output "resource_id" {
  description = "Resource ID of the DNS-servers assignment (equals the parent virtual network's resource ID)."
  value       = azapi_update_resource.this.id
}

output "dns_servers" {
  description = "The DNS servers assigned to the virtual network."
  value       = var.dns_servers
}

output "virtual_network_resource_id" {
  description = "Resource ID of the virtual network whose DNS servers are managed."
  value       = var.virtual_network_resource_id
}
