# Computed values are read through `try` because `terraform import` does not
# apply `response_export_values` — during an import the export is simply absent,
# and a bare reference would fail the whole evaluation.

output "resource_id" {
  description = "Resource ID of the managed cluster."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Cluster name."
  value       = azapi_resource.this.name
}

output "fqdn" {
  description = "Public FQDN of the API server. Null on a private cluster that does not enable `private_cluster_public_fqdn_enabled`."
  value       = try(azapi_resource.this.output.fqdn, null)
}

output "private_fqdn" {
  description = "Private FQDN of the API server. Null unless the cluster is private."
  value       = try(azapi_resource.this.output.private_fqdn, null)
}

output "resource_group_name" {
  description = <<-EOT
    Name of the resource group the cluster itself lives in — the one passed in,
    echoed back so a consumer holding a reference to the cluster does not have
    to reach for the resource group separately.

    Not to be confused with `node_resource_group_name`, which is the `MC_*`
    group AKS manages.
  EOT
  value       = var.resource_group_name
}

output "node_resource_group_name" {
  description = "Name of the resource group holding the cluster's own infrastructure — node scale sets, load balancers, and any identity an add-on creates for itself. Distinct from `resource_group_name`, which is where the cluster resource lives."
  value       = try(azapi_resource.this.output.node_resource_group, null)
}

output "oidc_issuer_url" {
  description = "Issuer URL for the cluster's OIDC endpoint, for the `issuer` of a federated identity credential. Null unless `oidc_issuer_enabled`."
  value       = try(azapi_resource.this.output.oidc_issuer_url, null)
}

output "current_kubernetes_version" {
  description = "The Kubernetes version the control plane is actually running, which an upgrade channel may have moved past the configured `kubernetes_version`."
  value       = try(azapi_resource.this.output.current_kubernetes_version, null)
}

output "system_assigned_mi_principal_id" {
  description = "Principal ID of the system-assigned managed identity, if `managed_identities.system_assigned = true`."
  value       = try(azapi_resource.this.identity[0].principal_id, null)
}

output "kubelet_identity" {
  description = <<-EOT
    The identity the nodes run as — `client_id`, `object_id` and
    `resource_id`. This is the principal that pulls images, so it is the one an
    `AcrPull` grant on a container registry goes to, not the control plane
    identity.
  EOT
  value = {
    client_id   = try(azapi_resource.this.output.kubelet_identity.clientId, null)
    object_id   = try(azapi_resource.this.output.kubelet_identity.objectId, null)
    resource_id = try(azapi_resource.this.output.kubelet_identity.resourceId, null)
  }
}

output "key_vault_secrets_provider_identity" {
  description = "Identity the Key Vault secrets provider add-on runs as — `client_id`, `object_id` and `resource_id`. All null when the add-on is disabled. Grant it access on the vaults the CSI driver has to read."
  value = {
    client_id   = try(azapi_resource.this.output.key_vault_secrets_provider_identity.clientId, null)
    object_id   = try(azapi_resource.this.output.key_vault_secrets_provider_identity.objectId, null)
    resource_id = try(azapi_resource.this.output.key_vault_secrets_provider_identity.resourceId, null)
  }
}

output "application_load_balancer_identity" {
  description = <<-EOT
    Identity the Application Gateway for Containers add-on creates for itself —
    `client_id`, `object_id` and `resource_id`. All null when the add-on is
    disabled.

    This is what needs Network Contributor on the AGfC subnet before a gateway
    will program. The identity is created by the add-on rather than by this
    module, so on the apply that first enables it the response may not carry the
    identity yet; it resolves on the next read. The identity is named
    `applicationloadbalancer-<cluster name>` in the node resource group if you
    need to reach it by name in the meantime.
  EOT
  value = {
    client_id   = try(azapi_resource.this.output.application_load_balancer_identity.clientId, null)
    object_id   = try(azapi_resource.this.output.application_load_balancer_identity.objectId, null)
    resource_id = try(azapi_resource.this.output.application_load_balancer_identity.resourceId, null)
  }
}

output "lock_resource_id" {
  description = "Resource ID of the management lock, or null when `lock` is unset."
  value       = try(azapi_resource.lock[0].id, null)
}

output "role_assignment_resource_ids" {
  description = "Resource IDs of the cluster-scope role assignments, keyed by the input map key."
  value       = { for k, v in azapi_resource.role_assignments : k => v.id }
}

output "diagnostic_setting_resource_ids" {
  description = "Resource IDs of the diagnostic settings, keyed by the input map key."
  value       = { for k, v in azapi_resource.diagnostic_settings : k => v.id }
}
