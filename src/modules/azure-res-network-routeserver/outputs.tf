# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the route server (a `Microsoft.Network/virtualHubs` resource). This is the `route_server_resource_id` for `modules/bgp-connection`."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the route server."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the route server (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "virtual_router_asn" {
  description = "ASN of the route server — what a peer NVA configures as the remote AS. Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.virtual_router_asn, null)
}

output "virtual_router_ips" {
  description = <<-EOT
    The route server's two peering addresses — a peer NVA should establish BGP with
    both.

    Read from the hub, which Azure fills in once the IP configuration has provisioned.
    The hub is created before its IP configuration, so the apply that creates the
    route server records none; the next refresh does. Null during an import, before
    the first refresh.
  EOT
  value       = try(azapi_resource.this.output.virtual_router_ips, null)
}

output "routing_state" {
  description = "Routing state of the route server (`Provisioned` once it is ready). Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.routing_state, null)
}

output "ip_configuration_resource_id" {
  description = "Resource ID of the route server's IP configuration."
  value       = azapi_resource.ip_configuration.id
}

output "public_ip" {
  description = "The route server's public IP: `resource_id`, `name` and `ip_address` (null during an import, before the first refresh)."
  value = {
    resource_id = azapi_resource.public_ip.id
    name        = azapi_resource.public_ip.name
    ip_address  = try(azapi_resource.public_ip.output.ip_address, null)
  }
}

output "diagnostic_settings" {
  description = "Map of diagnostic settings keyed by the input map key."
  value = {
    for k, v in azapi_resource.diagnostic_settings : k => {
      resource_id = v.id
      name        = v.name
    }
  }
}

output "role_assignments" {
  description = "Map of route-server-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the route server. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
