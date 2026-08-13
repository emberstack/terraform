output "private_dns_zone_vnet_links" {
  description = "Map of created vnet links keyed by the input map key. Each entry exposes `resource_id`, `name`, `private_dns_zone_resource_id`, and `virtual_network_resource_id`."
  value = {
    for k, v in azapi_resource.this : k => {
      resource_id                  = v.id
      name                         = v.name
      private_dns_zone_resource_id = var.private_dns_zone_vnet_links[k].private_dns_zone_resource_id
      virtual_network_resource_id  = var.private_dns_zone_vnet_links[k].virtual_network_resource_id
    }
  }
}
