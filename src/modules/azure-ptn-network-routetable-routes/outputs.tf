output "routes" {
  description = "Map of created routes, keyed by the input map key. Each entry exposes `resource_id`, `name`, `address_prefix`, `next_hop_type` and `next_hop_in_ip_address`."
  value = {
    for k, v in azapi_resource.this : k => {
      resource_id            = v.id
      name                   = v.name
      address_prefix         = var.routes[k].address_prefix
      next_hop_type          = var.routes[k].next_hop_type
      next_hop_in_ip_address = var.routes[k].next_hop_in_ip_address
    }
  }
}

output "route_table_resource_id" {
  description = "ARM resource ID of the route table the routes were written into, as supplied."
  value       = var.route_table_resource_id
}
