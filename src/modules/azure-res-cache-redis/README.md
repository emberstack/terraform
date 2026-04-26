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
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-cache-redis?ref=v0.1.0"

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

## Inputs

### Required

| Name | Type | Description |
|---|---|---|
| `name` | `string` | 1–63 chars, alphanumeric + hyphens. |
| `location` | `string` | Azure region. |
| `parent_id` | `string` | ARM resource ID of the parent resource group. |
| `sku_name` | `string` | E.g. `Balanced_B0`, `MemoryOptimized_M10`, `Enterprise_E5`. |

### Optional — AVM-style standard interfaces

| Name | Type | Default | Description |
|---|---|---|---|
| `tags` | `map(string)` | `null` | Cluster tags. |
| `lock` | `object({kind, name})` | `null` | Resource lock. `kind`: `CanNotDelete` or `ReadOnly`. |
| `managed_identities` | `object({system_assigned, user_assigned_resource_ids})` | both empty | Managed identities to attach. |
| `customer_managed_key_encryption` | `object({key_encryption_key_url, identity_type, user_assigned_identity_resource_id})` | `null` | CMK encryption (UAI required). |
| `role_assignments` | `map(object({...}))` | `{}` | Role assignments scoped to the cluster. |
| `private_endpoints` | `map(object({...}))` | `{}` | Private endpoints (with optional per-PE locks, role assignments, ASG associations, IP configs). |
| `private_endpoints_manage_dns_zone_group` | `bool` | `true` | Set to false to manage zone groups externally. |
| `diagnostic_settings` | `map(object({...}))` | `{}` | Cluster-level diagnostic settings. |

### Optional — cluster

| Name | Type | Default | Description |
|---|---|---|---|
| `high_availability` | `string` | `"Enabled"` | `Enabled` or `Disabled`. |
| `public_network_access` | `string` | `"Disabled"` | `Enabled` or `Disabled`. |

### Optional — database

| Name | Type | Default | Description |
|---|---|---|---|
| `clustering_policy` | `string` | `"EnterpriseCluster"` | `EnterpriseCluster`, `OSSCluster`, or `NoCluster`. **Immutable after creation.** |
| `eviction_policy` | `string` | `"AllKeysLRU"` | `AllKeysLRU`, `AllKeysRandom`, `VolatileLRU`, `VolatileRandom`, `VolatileTTL`, `NoEviction`. |
| `enable_non_ssl_port` | `bool` | `false` | Enables Plaintext client protocol when true. |
| `access_keys_authentication_enabled` | `bool` | `false` | Legacy access-keys auth. **Not exposed by upstream AVM.** |
| `persistence_append_only_file_backup_frequency` | `string` | `null` | E.g. `1s`, `always`. **Not exposed by upstream AVM.** |
| `persistence_redis_database_backup_frequency` | `string` | `null` | E.g. `1h`, `6h`, `12h`. **Not exposed by upstream AVM.** |
| `geo_replication_group_name` | `string` | `null` | Active-Active geo-replication group. |
| `redis_modules` | `list(object({name, args}))` | `[]` | RediSearch / RedisJSON / RedisBloom / RedisTimeSeries. |

## Outputs

| Name | Description |
|---|---|
| `resource_id` | Cluster ARM resource ID. |
| `name` | Cluster name. |
| `hostname` | FQDN. |
| `system_assigned_mi_principal_id` | Principal ID of the system-assigned identity (when enabled). |
| `default_database` | `{ id, port }`. |
| `private_endpoints` | Map of PE details. |
| `diagnostic_settings` | Map of diag-setting details. |
| `role_assignments` | Map of cluster-scoped role-assignment details. |
| `resource` | Full `azurerm_managed_redis` resource. Sensitive. |

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azurerm` `>= 4.81, < 5.0`

## Notes vs. the upstream AVM module

- **Provider.** This module uses `azurerm`, the AVM uses `azapi`. Practical implication: state addresses (`azurerm_managed_redis.this`, `azurerm_private_endpoint.this[<key>]`) are stable across migrations from older `azurerm`-based modules.
- **CMK identity.** Both modules require a user-assigned identity for CMK (the resource provider only supports `userAssignedIdentity` today). The `identity_type` field is kept for AVM compatibility but is validated to `UserAssignedIdentity`.
- **`zones`.** The AVM input is omitted because the `azurerm_managed_redis` resource does not expose zones directly — zone redundancy is implicit when `high_availability = "Enabled"` in regions with availability zones.
- **`access_policy_assignments`.** Not implemented — the `azurerm_managed_redis` resource doesn't model database-level access policies. If you need Entra-ID-only auth, use `access_keys_authentication_enabled = false` and manage policies via a sibling resource.
- **`clustering_policy = "NoCluster"`.** Allowed (the underlying provider accepts it). The AVM module restricts to `EnterpriseCluster | OSSCluster | NoEviction` — different semantics.
