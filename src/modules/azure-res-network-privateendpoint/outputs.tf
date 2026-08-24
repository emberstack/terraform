# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation. It also picks whichever
# of the two ARM connection arrays is populated. Note the `properties` hop:
# state sits at `[0].properties.privateLinkServiceConnectionState`, not on the
# connection object — get it wrong and `try` returns null instead of erroring.

output "resource_id" {
  description = "Resource ID of the private endpoint."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Private endpoint name."
  value       = azapi_resource.this.name
}

output "private_ip_address" {
  description = <<-EOT
    The endpoint's allocated private IP.

    ARM surfaces the address through the DNS zone group's record sets, falling back to
    `customDnsConfigs`. It is null until the endpoint has been created, stays null
    while a manual connection is `Pending`, and — without a DNS zone group — may stay
    null altogether.
  EOT
  value = try(
    flatten([for record in azapi_resource.dns_zone_group[0].output.record_sets : record.ipAddresses])[0],
    azapi_resource.this.output.custom_dns_configs[0].ipAddresses[0],
    null
  )
}

output "network_interface" {
  description = "The network interface ARM created for the endpoint."
  value       = try(azapi_resource.this.output.network_interfaces[0], null)
}

output "custom_dns_configs" {
  description = "The endpoint's `customDnsConfigs` — FQDNs and addresses to publish when DNS is managed outside this module."
  value       = try(azapi_resource.this.output.custom_dns_configs, null)
}

output "connection_status" {
  description = <<-EOT
    Approval status of the connection — `Pending`, `Approved`, `Rejected` or
    `Disconnected`.

    A manual connection applies as `Pending` and only carries traffic once the target's
    owner approves. Because approval happens outside Terraform, the value is read at
    refresh: a plan run before the owner acts still reports `Pending`.
  EOT
  value = try(
    azapi_resource.this.output.manual_connections[0].properties.privateLinkServiceConnectionState.status,
    azapi_resource.this.output.connections[0].properties.privateLinkServiceConnectionState.status,
    null
  )
}

output "connection_state" {
  description = "The full `privateLinkServiceConnectionState` — `status`, `description` and `actionsRequired`. `actionsRequired` is where a target reports that the consumer still has work to do after approval."
  value = try(
    azapi_resource.this.output.manual_connections[0].properties.privateLinkServiceConnectionState,
    azapi_resource.this.output.connections[0].properties.privateLinkServiceConnectionState,
    null
  )
}

output "dns_zone_group_resource_id" {
  description = "Resource ID of the private DNS zone group. Null when no zones were supplied, or when `manage_dns_zone_group = false`."
  value       = try(azapi_resource.dns_zone_group[0].id, null)
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the endpoint. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}

output "role_assignments" {
  description = "Map of role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}
