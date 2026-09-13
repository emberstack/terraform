# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Database name, unique within the server."
  nullable    = false

  # Azure rejects these characters outright, plus a trailing period or space.
  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 128 && !can(regex("[<>*%&:\\\\/?]", var.name)) && !can(regex("[. ]$", var.name))
    error_message = "name must be 1-128 characters, must not contain < > * % & : \\ / ?, and must not end with a period or space."
  }
}

variable "sql_server_resource_id" {
  type        = string
  description = "ARM resource ID of the SQL logical server. Used directly as the database's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Sql/servers/[^/]+$", var.sql_server_resource_id))
    error_message = "sql_server_resource_id must be a Microsoft.Sql/servers resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region. Must match the server's region - ARM rejects a database placed elsewhere."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional - placement and capacity
# -----------------------------------------------------------------------------

variable "elastic_pool_resource_id" {
  type        = string
  default     = null
  description = <<-EOT
    Resource ID of an elastic pool to place this database in. Null makes it a
    standalone database.

    A pooled database draws capacity and storage from the pool, so `sku` and
    `max_size_gb` must both be null - ARM rejects them alongside a pool.
  EOT
}

variable "sku" {
  type = object({
    name     = string
    tier     = optional(string, null)
    family   = optional(string, null)
    capacity = optional(number, null)
  })
  default     = null
  description = <<-EOT
    Service objective for a STANDALONE database - required for one, and must be
    null for a pooled database.

    Which combinations exist varies by region and offer, and ARM rejects an
    invalid one at apply rather than plan. The authoritative list is
    `az sql db list-editions -l <location> -o table`, so this is deliberately
    not validated against a hardcoded set.
  EOT
}

variable "max_size_gb" {
  type        = number
  default     = null
  description = <<-EOT
    Max database size, in GB. Converted to the bytes ARM expects, using Azure's
    own binary GB (1024^3) - so `250` sends `268435456000`.

    Must be null for a pooled database; the pool's limit applies instead.
  EOT

  validation {
    condition     = var.max_size_gb == null || var.max_size_gb > 0
    error_message = "max_size_gb must be a positive number of GB."
  }
}

variable "min_capacity" {
  type        = number
  default     = null
  description = "Serverless only: capacity the database keeps allocated while running. Null on a provisioned database."
}

variable "auto_pause_delay" {
  type        = number
  default     = null
  description = <<-EOT
    Serverless only: minutes of inactivity before the database auto-pauses.
    `-1` disables auto-pause. Null on a provisioned database - ARM reports `-1`
    there regardless, which is why nulls are not compared.
  EOT
}

variable "high_availability_replica_count" {
  type        = number
  default     = null
  description = "Secondary replicas for high availability. Business Critical, Premium and Hyperscale only, and not for a Hyperscale database inside a pool."
}

# -----------------------------------------------------------------------------
# Optional - engine
# -----------------------------------------------------------------------------

variable "collation" {
  type        = string
  default     = null
  description = <<-EOT
    Database collation, e.g. `SQL_Latin1_General_CP1_CI_AS`. Null takes Azure's
    default, which is that value.

    CANNOT BE CHANGED after creation. It is sent rather than omitted so that
    editing it produces an honest ARM error instead of being silently dropped.
  EOT
}

variable "catalog_collation" {
  type        = string
  default     = null
  description = "Collation of the metadata catalog. Null takes Azure's default. Cannot be changed after creation."
}

variable "ledger_enabled" {
  type        = bool
  default     = null
  description = <<-EOT
    Make every table in the database a ledger table, giving tamper-evident
    history.

    CANNOT BE CHANGED after creation - Microsoft states the value is fixed once
    the database exists.
  EOT
}

variable "preferred_enclave_type" {
  type        = string
  default     = null
  description = "`VBS` requests a virtualization-based secure enclave for Always Encrypted; `Default` requests none."

  validation {
    condition     = var.preferred_enclave_type == null || contains(["Default", "VBS"], var.preferred_enclave_type)
    error_message = "preferred_enclave_type must be one of: Default, VBS."
  }
}

variable "read_scale_enabled" {
  type        = bool
  default     = null
  description = "Route connections with `ApplicationIntent=ReadOnly` to a read-only replica. Requires a tier that has replicas."
}

variable "license_type" {
  type        = string
  default     = null
  description = "`LicenseIncluded` to pay for the SQL licence, or `BasePrice` to claim Azure Hybrid Benefit against one you already own. vCore tiers only."

  validation {
    condition     = var.license_type == null || contains(["BasePrice", "LicenseIncluded"], var.license_type)
    error_message = "license_type must be one of: BasePrice, LicenseIncluded."
  }
}

variable "maintenance_configuration_resource_id" {
  type        = string
  default     = null
  description = "Maintenance window configuration ID. Null leaves the database on the default window, which Azure may apply at any time."
}

# -----------------------------------------------------------------------------
# Optional - resilience
# -----------------------------------------------------------------------------

variable "zone_redundant" {
  type        = bool
  default     = null
  description = "Spread the database's replicas across availability zones. Requires a tier that HAS replicas - Basic and Standard do not."
}

variable "availability_zone" {
  type        = string
  default     = null
  description = "Pin the primary replica to a zone: `1`, `2`, `3`, or `NoPreference`. Meaningful only when `zone_redundant` is false."

  validation {
    condition     = var.availability_zone == null || contains(["1", "2", "3", "NoPreference"], var.availability_zone)
    error_message = "availability_zone must be one of: 1, 2, 3, NoPreference."
  }
}

variable "backup_storage_redundancy" {
  type        = string
  default     = null
  description = <<-EOT
    Where backups are stored: `Local` (single datacentre), `Zone` (across zones
    in the region) or `Geo` (paired region).

    `Geo` is the only one that survives a regional outage. Changing it applies
    to FUTURE backups only - existing ones stay where they were written.
  EOT

  validation {
    condition     = var.backup_storage_redundancy == null || contains(["Geo", "Local", "Zone"], var.backup_storage_redundancy)
    error_message = "backup_storage_redundancy must be one of: Geo, Local, Zone."
  }
}

# -----------------------------------------------------------------------------
# Optional - backup retention
# -----------------------------------------------------------------------------

variable "short_term_retention" {
  type = object({
    retention_days                        = number
    differential_backup_interval_in_hours = optional(number, null)
  })
  default     = null
  description = <<-EOT
    Point-in-time restore window. Null leaves Azure's default of 7 days.

    - `retention_days`: 1-35 on most tiers, up to 35 on Hyperscale.
    - `differential_backup_interval_in_hours`: 12 or 24.

    THIS DOES NOT SURVIVE THE SERVER. Deleting a logical server deletes its
    databases and their PITR backups together, and neither can be restored.
    Use `long_term_retention` for backups that outlive the server.
  EOT

  validation {
    condition     = var.short_term_retention == null || try(var.short_term_retention.retention_days, 0) >= 1
    error_message = "short_term_retention.retention_days must be at least 1."
  }

  validation {
    condition     = var.short_term_retention == null || var.short_term_retention.differential_backup_interval_in_hours == null || contains([12, 24], var.short_term_retention.differential_backup_interval_in_hours)
    error_message = "short_term_retention.differential_backup_interval_in_hours must be 12 or 24."
  }
}

variable "long_term_retention" {
  type = object({
    weekly_retention  = optional(string, null)
    monthly_retention = optional(string, null)
    yearly_retention  = optional(string, null)
    week_of_year      = optional(number, null)
  })
  default     = null
  description = <<-EOT
    Long-term backup retention, as ISO-8601 durations (`P4W`, `P12M`, `P7Y`).
    Null leaves LTR unconfigured.

    `week_of_year` (1-52) picks which weekly backup is kept for the year and is
    REQUIRED whenever `yearly_retention` is set - ARM keeps no yearly backup
    without it.

    LTR is the ONLY backup class that survives deletion of the logical server,
    and it can be restored to a different server. A database with PITR alone is
    unrecoverable once its server is gone. An unset policy reads back as `PT0S`
    on every field, which is indistinguishable from having none.
  EOT

  validation {
    condition = var.long_term_retention == null || alltrue([
      for d in compact([
        try(var.long_term_retention.weekly_retention, null),
        try(var.long_term_retention.monthly_retention, null),
        try(var.long_term_retention.yearly_retention, null),
      ]) : can(regex("^P[0-9]+[DWMY]$", d))
    ])
    error_message = "long_term_retention durations must be ISO-8601 like P4W, P12M or P7Y."
  }

  validation {
    condition     = var.long_term_retention == null || try(var.long_term_retention.yearly_retention, null) == null || try(var.long_term_retention.week_of_year, null) != null
    error_message = "long_term_retention.week_of_year is required when yearly_retention is set - ARM keeps no yearly backup without it."
  }

  validation {
    condition     = var.long_term_retention == null || try(var.long_term_retention.week_of_year, null) == null || (var.long_term_retention.week_of_year >= 1 && var.long_term_retention.week_of_year <= 52)
    error_message = "long_term_retention.week_of_year must be between 1 and 52."
  }
}

# -----------------------------------------------------------------------------
# Optional - encryption and identity
# -----------------------------------------------------------------------------

variable "managed_identities" {
  type = object({
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    User-assigned identities on the DATABASE. Separate from the server's, and
    required for database-level customer-managed TDE.

    Azure SQL databases do not support a system-assigned identity, so only the
    user-assigned set is exposed.
  EOT
  nullable    = false
}

variable "customer_managed_key" {
  type = object({
    key_vault_key_uri     = string
    auto_rotation_enabled = optional(bool, true)
  })
  default     = null
  description = <<-EOT
    Database-level customer-managed key for TDE. Null inherits the server's TDE
    protector, which is the usual arrangement - set this only to give one
    database a different key from its server.

    Pass a VERSIONED URI. ARM accepts a versionless one but normalises it to the
    versioned form, so a versionless config never matches the response and diffs
    forever; `auto_rotation_enabled` is what follows rotation.

    Requires an identity in `managed_identities.user_assigned_resource_ids` that
    already holds wrap/unwrap on the key - this module does not create that
    grant.
  EOT

  validation {
    condition     = var.customer_managed_key == null || can(regex("^https://[^/.]+\\.[^/]+/keys/[^/]+(/[^/]+)?$", try(var.customer_managed_key.key_vault_key_uri, "")))
    error_message = "customer_managed_key.key_vault_key_uri must look like https://<vault>.vault.azure.net/keys/<key> with an optional /<version> suffix."
  }
}

variable "federated_client_id" {
  type        = string
  default     = null
  description = "Client ID of the multi-tenant application used for a cross-tenant database-level customer-managed key. Leave null for same-tenant CMK."

  validation {
    condition     = var.federated_client_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.federated_client_id))
    error_message = "federated_client_id must be a GUID."
  }
}

# -----------------------------------------------------------------------------
# Optional - access
# -----------------------------------------------------------------------------

variable "role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Role assignments scoped to the database, keyed by stable name.

    These are ARM control-plane roles. They do NOT grant access to the data
    inside the database - that is a SQL-level grant made through the Entra
    administrator, not through RBAC.

    `role_definition_id_or_name` accepts either a role name (e.g. `"Reader"`) or
    a full role definition resource ID. Auto-routed by the leading `/`.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal
    or a managed identity, so ARM skips the directory lookup that fails on a principal
    created moments earlier.
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
# Optional - diagnostics
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
    Diagnostic settings on the database, keyed by stable name.

    `SQLSecurityAuditEvents` is a category HERE, not on the server. Server-level
    auditing writes into the `master` database, so shipping audit logs means a
    setting on that database carrying this category.

    Exactly one destination must be set per entry.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional - protection
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
    - `name`: optional. Defaults to `lock-<database-name>`.

    A lock on the database does NOT stop the server being deleted, which takes
    the database with it. Lock the server as well if that is the risk.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

# -----------------------------------------------------------------------------
# Optional - metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the database."
}
