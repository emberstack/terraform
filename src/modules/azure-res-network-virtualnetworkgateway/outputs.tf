# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the virtual network gateway."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the virtual network gateway."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the gateway (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "bgp_asn" {
  description = "ASN of the gateway's BGP speaker as ARM reports it — Azure's default when `vpn_bgp_settings` is unset. Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.bgp_asn, null)
}

output "ip_configurations" {
  description = <<-EOT
    Map of the gateway's IP configurations, keyed by the input map key.

    - `resource_id`: the IP configuration's ARM ID — what a connection's custom BGP
      address selection references.
    - `public_ip_address_resource_id`: echoes the input.
    - `private_ip_address`: the instance's address in `GatewaySubnet`.
    - `default_bgp_ip_addresses`: the BGP peer addresses Azure assigned from
      `GatewaySubnet`.
    - `custom_bgp_ip_addresses`: the APIPA addresses in effect.
    - `tunnel_ip_addresses`: the instance's tunnel endpoints, public address included.

    ARM-reported values are null during an import, before the first refresh, and
    wherever ARM reports none.
  EOT
  value = {
    for key, config in var.ip_configurations : key => {
      resource_id                   = "${azapi_resource.this.id}/ipConfigurations/${key}"
      public_ip_address_resource_id = config.public_ip_address_resource_id
      private_ip_address = try(one([
        for ip in azapi_resource.this.output.ip_configurations : ip.private_ip_address if ip.name == key
      ]), null)
      default_bgp_ip_addresses = try(one([
        for peering in azapi_resource.this.output.bgp_peering_addresses : peering.default_ip_addresses
        if lower(basename(peering.ip_configuration_id)) == lower(key)
      ]), null)
      custom_bgp_ip_addresses = try(one([
        for peering in azapi_resource.this.output.bgp_peering_addresses : peering.custom_ip_addresses
        if lower(basename(peering.ip_configuration_id)) == lower(key)
      ]), null)
      tunnel_ip_addresses = try(one([
        for peering in azapi_resource.this.output.bgp_peering_addresses : peering.tunnel_ip_addresses
        if lower(basename(peering.ip_configuration_id)) == lower(key)
      ]), null)
    }
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
  description = "Map of gateway-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the gateway. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
