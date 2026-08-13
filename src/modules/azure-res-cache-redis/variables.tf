# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the Azure Managed Redis (Redis Enterprise) cluster."
  nullable    = false

  # ARM's own pattern is `^(?=.{1,60}$)[A-Za-z0-9]+(-[A-Za-z0-9]+)*$`, described as
  # "1-60 characters ... There can be no leading nor trailing nor consecutive
  # hyphens". Terraform's regex engine is RE2 and has no lookahead, so the length
  # half is checked separately; the alternation covers all three hyphen rules by
  # itself. Checked 2026-08-13 against ClusterNameParameter in the redisenterprise
  # 2025-07-01 swagger — note 60, not 63, and a LEADING hyphen is rejected too.
  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 60 && can(regex("^[A-Za-z0-9]+(-[A-Za-z0-9]+)*$", var.name))
    error_message = "name must be 1–60 characters of letters, digits and hyphens, with no leading, trailing or consecutive hyphens."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the cluster should be deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the cluster will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
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

# -----------------------------------------------------------------------------
# Optional — cluster
# -----------------------------------------------------------------------------

variable "high_availability_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether high availability is on. Default: true — primary and replica shards
    across two nodes, zone-redundant in regions with availability zones. False
    gives a single shard: halves the cost, and is only suitable for dev/test.
  EOT
  nullable    = false
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether the cluster is reachable from the public internet. Default: false.

    Deliberately the opposite default to the input of the same name on
    `azure-res-signalrservice-signalr`. A cache holds data and is normally reached
    over a private endpoint, so closed is the posture to fall into by accident.
    Matching the two defaults would open every cluster that never set this.
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

# -----------------------------------------------------------------------------
# Optional — database
# -----------------------------------------------------------------------------
# These map onto the cluster's default database (every Redis Enterprise cluster
# has exactly one database named `default`).

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

variable "non_ssl_port_enabled" {
  type        = bool
  default     = false
  description = "Whether the non-SSL port is open (the Plaintext client protocol). Default: false — Encrypted only."
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

  validation {
    condition = (
      var.persistence_append_only_file_backup_frequency == null ||
      var.persistence_redis_database_backup_frequency == null
    )
    error_message = "persistence_append_only_file_backup_frequency and persistence_redis_database_backup_frequency are mutually exclusive — set at most one."
  }
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

variable "port" {
  type        = number
  default     = 10000
  description = "TCP port the default database listens on. Sent explicitly for the same reason as `minimum_tls_version` — clients break if it moves."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — identity
# -----------------------------------------------------------------------------

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

    When `customer_managed_key_encryption` is set, a UAI must be attached: only
    `UserAssignedIdentity` is supported by the Microsoft.Cache/redisEnterprise
    API today.
  EOT
  nullable    = false
}

variable "customer_managed_key_encryption" {
  type = object({
    key_encryption_key_url             = string
    identity_type                      = optional(string, "UserAssignedIdentity")
    user_assigned_identity_resource_id = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Customer-managed key (CMK) encryption settings. Mirrors the AVM shape.

    - `key_encryption_key_url`: full versioned key URL
      (e.g. `https://<vault>.vault.azure.net/keys/<name>/<version>`).
    - `identity_type`: which identity fetches the key. Optional — the only value
      Microsoft.Cache/redisEnterprise implements today is `UserAssignedIdentity`,
      which is the default. The ARM schema also declares `systemAssignedIdentity`
      but documents it as unsupported in every version through `2025-07-01`.
    - `user_assigned_identity_resource_id`: ARM resource ID of the UAI used
      to fetch the key. Must also be present in
      `managed_identities.user_assigned_resource_ids`.
  EOT

  # Paired with `local.customer_managed_key_identity_types` in main.tf, which maps
  # the accepted value to ARM's own casing. Widen both or neither.
  validation {
    condition     = var.customer_managed_key_encryption == null || contains(["UserAssignedIdentity"], var.customer_managed_key_encryption.identity_type)
    error_message = "customer_managed_key_encryption.identity_type must be 'UserAssignedIdentity' (the only value the resource provider implements today)."
  }

  validation {
    condition     = var.customer_managed_key_encryption == null || try(var.customer_managed_key_encryption.user_assigned_identity_resource_id, null) != null
    error_message = "customer_managed_key_encryption.user_assigned_identity_resource_id is required when customer_managed_key_encryption is set."
  }
}

# -----------------------------------------------------------------------------
# Optional — networking
# -----------------------------------------------------------------------------

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
  description = <<-EOT
    Private endpoints keyed by stable name. Shape mirrors AVM standard.

    Keys of this map, and of each nested `role_assignments` map, must be snake_case
    handles: a per-endpoint role assignment's state address is the two keys joined
    with `-`, so the keys themselves must not contain that separator.

    `skip_service_principal_aad_check` is accepted for interface compatibility and has
    no effect. ARM's equivalent is `principalType`, which this module already
    exposes: set `principal_type = "ServicePrincipal"` so ARM skips the directory
    lookup that fails on a principal created moments earlier.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : can(regex("^[a-z0-9]+(_[a-z0-9]+)*$", k))])
    error_message = <<-EOT
      Every private_endpoints key must match ^[a-z0-9]+(_[a-z0-9]+)*$ (lower-case
      snake_case). A per-endpoint role assignment is addressed in state by joining
      the endpoint key and the assignment key with "-", so a key containing "-"
      would let two different pairs collide on one address: ("a-b", "c") and
      ("a", "b-c") both produce "a-b-c".
    EOT
  }

  validation {
    condition = alltrue(flatten([
      for pe_k, pe_v in var.private_endpoints : [
        for ra_k in keys(pe_v.role_assignments) : can(regex("^[a-z0-9]+(_[a-z0-9]+)*$", ra_k))
      ]
    ]))
    error_message = <<-EOT
      Every key of a private_endpoints[*].role_assignments map must match
      ^[a-z0-9]+(_[a-z0-9]+)*$ (lower-case snake_case), for the same reason as the
      endpoint keys: the two are joined with "-" to form the state address.
    EOT
  }
}

variable "private_endpoints_manage_dns_zone_group" {
  type        = bool
  default     = true
  description = "Whether the module manages private DNS zone groups. Set to false to manage zone groups externally (e.g. via Azure Policy)."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — access
# -----------------------------------------------------------------------------

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
    no effect. ARM's equivalent is `principalType`, which this module already
    exposes: set `principal_type = "ServicePrincipal"` so ARM skips the directory
    lookup that fails on a principal created moments earlier.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in var.role_assignments :
      assignment.name == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", assignment.name))
    ])
    error_message = "role_assignments `name`, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
  }
}

# -----------------------------------------------------------------------------
# Optional — diagnostics
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Optional — protection
# -----------------------------------------------------------------------------

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

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the cluster."
}
