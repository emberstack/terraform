output "resource_id" {
  description = "ARM resource ID of the virtual network link."
  value       = azurerm_private_dns_zone_virtual_network_link.this.id
}

output "name" {
  description = "Name of the virtual network link."
  value       = azurerm_private_dns_zone_virtual_network_link.this.name
}
