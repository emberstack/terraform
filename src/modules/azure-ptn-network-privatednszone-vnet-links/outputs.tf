output "private_dns_zone_vnet_links" {
  description = "Map of created vnet links keyed by the input map key. Each entry exposes `id`, `name`, `private_dns_zone_resource_id`, and `virtual_network_resource_id`."
  value = {
    for k, v in azurerm_private_dns_zone_virtual_network_link.this : k => {
      id                           = v.id
      name                         = v.name
      private_dns_zone_resource_id = var.private_dns_zone_vnet_links[k].private_dns_zone_resource_id
      virtual_network_resource_id  = v.virtual_network_id
    }
  }
}
