# =============================================================================
# Required AVM-style interfaces
# =============================================================================

variable "name" {
  type        = string
  description = "The name of the Azure Managed Redis (Redis Enterprise) cluster."
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9-]{1,63}$", var.name)) && !can(regex("--", var.name)) && !can(regex("-$", var.name))
    error_message = "name must be 1–63 chars, alphanumeric and hyphens, no consecutive hyphens, and not ending with a hyphen."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the cluster should be deployed."
  nullable    = false
}

variable "parent_id" {
  type        = string
  description = "Resource ID of the parent resource group. Mirrors AVM `parent_id` (the cluster RG must already exist)."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.parent_id))
    error_message = "parent_id must be a resource group ARM resource ID, e.g. /subscriptions/<sub>/resourceGroups/<rg>."
  }
}

variable "sku_name" {
  type        = string
  description = <<-EOT
    SKU name. Examples:
    - Memory-Optimized: MemoryOptimized_M10, MemoryOptimized_M20
    - Balanced:         Balanced_B0, Balanced_B1, Balanced_B3, Balanced_B5
    - Compute-Optimized: ComputeOptimized_X5, ComputeOptimized_X10
    - Flash-Optimized:   FlashOptimized_A250, FlashOptimized_A500
  EOT
  nullable    = false
}

# =============================================================================
# Standard AVM-style optional interfaces
# =============================================================================

variable "tags" {
  type        = map(string)
  default     = null
  description = "Tags applied to the cluster."
}

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Resource lock configuration.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<cluster-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    Managed identity configuration for the cluster.

    - `system_assigned`: enable a system-assigned identity.
    - `user_assigned_resource_ids`: set of UAI resource IDs to attach.

    When `customer_managed_key_encryption` is set, a UAI must be attached
    (the AzureRM provider's `customer_managed_key` block requires
    `user_assigned_identity_id`).
  EOT
  nullable    = false
}

variable "customer_managed_key_encryption" {
  type = object({
    key_encryption_key_url             = string
    identity_type                      = string
    user_assigned_identity_resource_id = optional(string)
  })
  default     = null
  description = <<-EOT
    Customer-managed key (CMK) encryption settings. Mirrors the AVM shape.

    - `key_encryption_key_url`: full versioned key URL
      (e.g. `https://<vault>.vault.azure.net/keys/<name>/<version>`).
    - `identity_type`: only `UserAssignedIdentity` is supported by the
      Microsoft.Cache/redisEnterprise API today.
    - `user_assigned_identity_resource_id`: ARM resource ID of the UAI used
      to fetch the key. Must also be present in
      `managed_identities.user_assigned_resource_ids`.
  EOT

  validation {
    condition     = var.customer_managed_key_encryption == null || try(var.customer_managed_key_encryption.identity_type, "") == "UserAssignedIdentity"
    error_message = "customer_managed_key_encryption.identity_type must be 'UserAssignedIdentity' (the only value the resource provider accepts today)."
  }

  validation {
    condition     = var.customer_managed_key_encryption == null || try(var.customer_managed_key_encryption.user_assigned_identity_resource_id, null) != null
    error_message = "customer_managed_key_encryption.user_assigned_identity_resource_id is required when customer_managed_key_encryption is set."
  }
}

variable "role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Role assignments scoped to the cluster, keyed by stable name.

    `role_definition_id_or_name` accepts either a role name (e.g. `"Reader"`) or
    a full role definition resource ID. Auto-routed by the leading `/`.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is
    generated — unless you are adopting an assignment that already exists, where the
    existing GUID must be supplied to avoid a destroy-and-recreate.

    `skip_service_principal_aad_check` is accepted for interface compatibility and has
    no effect: the check is an `azurerm` provider behaviour with no ARM equivalent.
  EOT
  nullable    = false
}

variable "private_endpoints" {
  type = map(object({
    name = optional(string, null)
    role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      skip_service_principal_aad_check       = optional(bool, false)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string, null)
    }), null)
    tags                                    = optional(map(string), null)
    subnet_resource_id                      = string
    subresource_name                        = optional(string, "redisEnterprise")
    private_dns_zone_group_name             = optional(string, "default")
    private_dns_zone_resource_ids           = optional(set(string), [])
    application_security_group_associations = optional(map(string), {})
    private_service_connection_name         = optional(string, null)
    network_interface_name                  = optional(string, null)
    location                                = optional(string, null)
    resource_group_name                     = optional(string, null)
    ip_configurations = optional(map(object({
      name               = string
      private_ip_address = string
      subresource_name   = optional(string, null)
      member_name        = optional(string, null)
    })), {})
  }))
  default     = {}
  description = "Private endpoints keyed by stable name. Shape mirrors AVM standard."
  nullable    = false
}

variable "private_endpoints_manage_dns_zone_group" {
  type        = bool
  default     = true
  description = "Whether the module manages private DNS zone groups. Set to false to manage zone groups externally (e.g. via Azure Policy)."
  nullable    = false
}

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), ["AllMetrics"])
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the cluster, keyed by stable name. Cluster-level
    diagnostics only — Microsoft.Cache/redisEnterprise emits AllMetrics; logs
    are emitted at the database level (handled at the resource API).

    Exactly one destination must be set per entry.
  EOT
  nullable    = false
}

# =============================================================================
# Cluster-specific inputs (mirroring AVM where applicable)
# =============================================================================

variable "high_availability" {
  type        = string
  default     = "Enabled"
  description = <<-EOT
    High-availability mode: `Enabled` (default — primary + replica shards across
    two nodes, zone-redundant in regions with AZs) or `Disabled` (single shard;
    halves cost; only suitable for dev/test).
  EOT
  nullable    = false

  validation {
    condition     = contains(["Enabled", "Disabled"], var.high_availability)
    error_message = "high_availability must be 'Enabled' or 'Disabled'."
  }
}

variable "public_network_access" {
  type        = string
  default     = "Disabled"
  description = "Whether the cluster is reachable from the public internet. `Enabled` or `Disabled` (default)."
  nullable    = false

  validation {
    condition     = contains(["Enabled", "Disabled"], var.public_network_access)
    error_message = "public_network_access must be 'Enabled' or 'Disabled'."
  }
}

# =============================================================================
# Database-specific inputs
# =============================================================================
# These map onto the cluster's default database (every Redis Enterprise cluster
# has exactly one database named `default`).
# =============================================================================

variable "clustering_policy" {
  type        = string
  default     = "EnterpriseCluster"
  description = <<-EOT
    Clustering policy. Immutable after creation.

    - `EnterpriseCluster`: single endpoint, automatic sharding (default).
    - `OSSCluster`: Redis Cluster API protocol, best performance.
    - `NoCluster`: non-clustered mode (max 25 GB).
  EOT
  nullable    = false

  validation {
    condition     = contains(["EnterpriseCluster", "OSSCluster", "NoCluster"], var.clustering_policy)
    error_message = "clustering_policy must be one of: EnterpriseCluster, OSSCluster, NoCluster."
  }
}

variable "eviction_policy" {
  type        = string
  default     = "AllKeysLRU"
  description = <<-EOT
    Eviction policy when memory limit is reached.

    Possible values: `AllKeysLRU`, `AllKeysRandom`, `VolatileLRU`,
    `VolatileRandom`, `VolatileTTL`, `NoEviction`.
  EOT
  nullable    = false

  validation {
    condition     = contains(["AllKeysLRU", "AllKeysRandom", "VolatileLRU", "VolatileRandom", "VolatileTTL", "NoEviction"], var.eviction_policy)
    error_message = "eviction_policy must be one of: AllKeysLRU, AllKeysRandom, VolatileLRU, VolatileRandom, VolatileTTL, NoEviction."
  }
}

variable "enable_non_ssl_port" {
  type        = bool
  default     = false
  description = "Enable the non-SSL port (Plaintext client protocol). Default: false (Encrypted only)."
  nullable    = false
}

variable "access_keys_authentication_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether legacy access-keys authentication is enabled on the database.

    Default: false (Entra-only auth via access policy assignments). Set to true
    when callers can't yet use Entra-ID-based passwordless auth.

    **Not exposed by the upstream AVM module** — added here to cover the gap.
  EOT
  nullable    = false
}

variable "persistence_append_only_file_backup_frequency" {
  type        = string
  default     = null
  description = <<-EOT
    AOF persistence backup frequency. Common values: `1s`, `always`.

    Mutually exclusive with `persistence_redis_database_backup_frequency`.

    **Not exposed by the upstream AVM module** — added here to cover the gap.
  EOT
}

variable "persistence_redis_database_backup_frequency" {
  type        = string
  default     = null
  description = <<-EOT
    RDB persistence backup frequency. Common values: `1h`, `6h`, `12h`.

    Mutually exclusive with `persistence_append_only_file_backup_frequency`.

    **Not exposed by the upstream AVM module** — added here to cover the gap.
  EOT
}

variable "geo_replication_group_name" {
  type        = string
  default     = null
  description = "Active geo-replication group name. Set to join an Active-Active geo-replication group."
}

variable "redis_modules" {
  type = list(object({
    name = string
    args = optional(string, null)
  }))
  default     = []
  description = <<-EOT
    Redis modules to enable on the database.

    - `RediSearch` — full-text search (requires `EnterpriseCluster`).
    - `RedisJSON` — JSON data type support.
    - `RedisBloom` — probabilistic data structures.
    - `RedisTimeSeries` — time-series data structures.

    Adding/removing modules is destructive (cluster recreation).
  EOT
  nullable    = false
}

variable "minimum_tls_version" {
  type        = string
  default     = "1.2"
  description = <<-EOT
    Minimum TLS version the cluster accepts. Sent on every write rather than left to the service
    default, so an existing value can never be silently reset by an unrelated change.

    AVM `avm-res-cache-redisenterprise` does not expose this — emberstack does.
  EOT
  nullable    = false

  validation {
    condition     = contains(["1.0", "1.1", "1.2"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be one of: 1.0, 1.1, 1.2."
  }
}

variable "port" {
  type        = number
  default     = 10000
  description = "TCP port the default database listens on. Sent explicitly for the same reason as `minimum_tls_version` — clients break if it moves."
  nullable    = false
}
