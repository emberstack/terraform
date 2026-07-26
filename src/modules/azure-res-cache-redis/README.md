# Azure Managed Redis (Redis Enterprise)

Terraform module for **Azure Managed Redis** (`Microsoft.Cache/redisEnterprise`). Mirrors the input/output surface of the upstream AVM module [`Azure/avm-res-cache-redisenterprise/azurerm`](https://github.com/Azure/terraform-azurerm-avm-res-cache-redisenterprise) as closely as possible, but with two deliberate differences:

1. Uses the `azurerm` provider (not `azapi`) — keeps state addresses stable when migrating from the older `azurerm_managed_redis`-based modules.
2. Exposes a few features the AVM module does not yet support:
   - `access_keys_authentication_enabled`
   - `persistence_append_only_file_backup_frequency`
   - `persistence_redis_database_backup_frequency`
   - `geo_replication_group_name`
   - cluster-level `diagnostic_settings` (built-in, not a sidecar extension)

The module does **not** create the parent resource group — pass an existing one via `parent_id`.

## Usage

### Minimal

```hcl
module "redis" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-cache-redis?ref=vX.Y.Z"

  name      = "my-redis-cluster"
  location  = "westeurope"
  parent_id = azurerm_resource_group.example.id
  sku_name  = "Balanced_B0"
}
```

### CMK encryption with user-assigned identity

The `customer_managed_key` block in the AzureRM provider requires a user-assigned identity. Pass the same UAI in both `managed_identities.user_assigned_resource_ids` (so the cluster identity references it) and `customer_managed_key_encryption.user_assigned_identity_resource_id` (so the CMK block uses it).

```hcl
module "redis" {
  source = "..."

  name      = "my-redis-cluster"
  location  = "westeurope"
  parent_id = azurerm_resource_group.example.id
  sku_name  = "Balanced_B0"

  managed_identities = {
    user_assigned_resource_ids = [azurerm_user_assigned_identity.cmk.id]
  }

  customer_managed_key_encryption = {
    key_encryption_key_url             = "https://my-vault.vault.azure.net/keys/redis-cmk/abc123"
    identity_type                      = "UserAssignedIdentity"
    user_assigned_identity_resource_id = azurerm_user_assigned_identity.cmk.id
  }
}
```

### Persistence (AOF) and access-keys auth

Two features the upstream AVM module does not expose — set them when migrating workloads that depend on durable persistence and legacy auth.

```hcl
module "redis" {
  source = "..."

  # ...

  clustering_policy                             = "NoCluster"
  access_keys_authentication_enabled            = true
  persistence_append_only_file_backup_frequency = "1s"
}
```

### Private endpoint with private DNS zone group

```hcl
module "redis" {
  source = "..."

  # ...

  private_endpoints = {
    default = {
      subnet_resource_id            = azurerm_subnet.private_endpoints.id
      private_dns_zone_resource_ids = [azurerm_private_dns_zone.redis.id]
    }
  }
}
```

### Cluster-scoped role assignments

```hcl
module "redis" {
  source = "..."

  # ...

  role_assignments = {
    operators = {
      role_definition_id_or_name = "Redis Cache Contributor"
      principal_id               = azuread_group.operators.object_id
      principal_type             = "Group"
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes vs. the upstream AVM module

- **Provider.** This module uses `azurerm`, the AVM uses `azapi`. Practical implication: state addresses (`azurerm_managed_redis.this`, `azurerm_private_endpoint.this[<key>]`) are stable across migrations from older `azurerm`-based modules.
- **CMK identity.** Both modules require a user-assigned identity for CMK (the resource provider only supports `userAssignedIdentity` today). The `identity_type` field is kept for AVM compatibility but is validated to `UserAssignedIdentity`.
- **`zones`.** The AVM input is omitted because the `azurerm_managed_redis` resource does not expose zones directly — zone redundancy is implicit when `high_availability = "Enabled"` in regions with availability zones.
- **`access_policy_assignments`.** Not implemented — the `azurerm_managed_redis` resource doesn't model database-level access policies. If you need Entra-ID-only auth, use `access_keys_authentication_enabled = false` and manage policies via a sibling resource.
- **`clustering_policy = "NoCluster"`.** Allowed (the underlying provider accepts it). The AVM module restricts to `EnterpriseCluster | OSSCluster | NoEviction` — different semantics.
