# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the managed domain."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the `Microsoft.AAD/domainServices` resource."
  value       = azapi_resource.this.name
}

output "resource_group_name" {
  description = "Name of the resource group containing the managed domain (echoes `var.resource_group_name`)."
  value       = var.resource_group_name
}

output "domain_name" {
  description = "DNS name of the managed domain (echoes `var.domain_name`)."
  value       = var.domain_name
}

output "deployment_id" {
  description = "The managed domain's deployment ID, as ARM reports it. Null during an import, before the first refresh."
  value       = try(azapi_resource.this.output.deployment_id, null)
}

output "replica_sets" {
  description = <<-EOT
    The managed domain's replica sets, initial first, then `replica_sets` in input
    order.

    - `location`, `subnet_resource_id`: echo the input.
    - `replica_set_id`: the replica set's ID, assigned by ARM.
    - `domain_controller_ip_addresses`: the replica set's domain controllers.
    - `external_access_ip_address`: the public address secure LDAP is published on
      when external access is enabled.

    ARM-reported values are null during an import, before the first refresh, and
    wherever ARM reports none — including `domain_controller_ip_addresses` for up
    to an hour after a create, while the controllers are still provisioning.
  EOT
  value = [
    for replica_set in local.replica_set_outputs : {
      location                       = replica_set.location
      subnet_resource_id             = replica_set.subnet_resource_id
      replica_set_id                 = try(replica_set.arm.replica_set_id, null)
      domain_controller_ip_addresses = try(replica_set.arm.domain_controller_ip_addresses, null)
      external_access_ip_address     = try(replica_set.arm.external_access_ip_address, null)
    }
  ]
}

output "domain_controller_ip_addresses" {
  description = <<-EOT
    Every domain controller address across all replica sets, initial replica set
    first — what the managed domain's virtual network uses as its DNS servers, and
    what conditional forwarders elsewhere point at.

    Empty for up to an hour after a create, while the controllers are still
    provisioning, and during an import before the first refresh. Guard consumers
    that write DNS settings on its length: an empty server list on a virtual
    network means Azure-provided DNS, not "unchanged".
  EOT
  value = flatten([
    for replica_set in local.replica_set_outputs : coalesce(try(replica_set.arm.domain_controller_ip_addresses, null), [])
  ])
}

output "secure_ldap" {
  description = <<-EOT
    The installed secure LDAP certificate, as ARM reports it. Null when `secure_ldap`
    is not set.

    - `certificate_thumbprint`: thumbprint of the installed certificate.
    - `certificate_not_after`: its expiry — what to alert on, since the service
      does not renew it.
  EOT
  value = var.secure_ldap == null ? null : {
    certificate_thumbprint = try(azapi_resource.this.output.certificate_thumbprint, null)
    certificate_not_after  = try(azapi_resource.this.output.certificate_not_after, null)
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
  description = "Map of managed-domain-scope role assignments keyed by the input map key."
  value = {
    for k, v in azapi_resource.role_assignments : k => {
      resource_id  = v.id
      principal_id = var.role_assignments[k].principal_id
    }
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock on the managed domain. Null when `lock` is not set."
  value       = try(azapi_resource.lock[0].id, null)
}
