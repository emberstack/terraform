# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the elastic pool, unique within the server."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 128
    error_message = "name must be 1-128 characters."
  }
}

variable "sql_server_resource_id" {
  type        = string
  description = "ARM resource ID of the SQL logical server. Used directly as the pool's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Sql/servers/[^/]+$", var.sql_server_resource_id))
    error_message = "sql_server_resource_id must be a Microsoft.Sql/servers resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region. Must match the server's region - ARM rejects a pool placed elsewhere."
  nullable    = false
}

variable "sku" {
  type = object({
    name     = string
    tier     = optional(string, null)
    family   = optional(string, null)
    capacity = optional(number, null)
    size     = optional(string, null)
  })
  description = <<-EOT
    Pool SKU. `name` is the service objective (`GP_Gen5`, `BC_Gen5`,
    `StandardPool`, `PremiumPool`, `HS_Gen5`); `capacity` is vCores on a vCore
    SKU and DTUs on a DTU SKU.

    Which combinations exist varies by region and offer, and ARM rejects an
    invalid one at apply rather than plan. The authoritative list is
    `az sql elastic-pool list-editions -l <location> -o table`, so this is
    deliberately not validated against a hardcoded set.
  EOT
  nullable    = false
}

variable "per_database_settings" {
  type = object({
    min_capacity = number
    max_capacity = number
  })
  description = <<-EOT
    Floor and ceiling, per database, in the pool's capacity unit. `min_capacity`
    is reserved for every database in the pool, so `min * database count` cannot
    exceed the pool's capacity.

    Always sent: ARM fills it with the tier's own bounds when omitted, and a
    full-replace update would silently widen what one database may consume.
  EOT
  nullable    = false

  validation {
    condition     = var.per_database_settings.min_capacity >= 0 && var.per_database_settings.max_capacity >= var.per_database_settings.min_capacity
    error_message = "per_database_settings.min_capacity must be >= 0 and max_capacity must be >= min_capacity."
  }
}

# -----------------------------------------------------------------------------
# Optional - capacity
# -----------------------------------------------------------------------------

variable "max_size_gb" {
  type        = number
  default     = null
  description = <<-EOT
    Storage limit for the whole pool, in GB. Converted to the bytes ARM expects,
    using Azure's own binary GB (1024^3) - so `100` sends `107374182400`.

    Null leaves the tier default. The ceiling is a property of the SKU and
    capacity, not a free choice.
  EOT

  validation {
    condition     = var.max_size_gb == null || var.max_size_gb > 0
    error_message = "max_size_gb must be a positive number of GB."
  }
}

variable "min_capacity" {
  type        = number
  default     = null
  description = "Serverless only: capacity the pool will not shrink below while running. Null on a provisioned pool."
}

variable "auto_pause_delay" {
  type        = number
  default     = null
  description = <<-EOT
    Serverless only: minutes of inactivity before the pool auto-pauses. `-1`
    disables auto-pause. Null on a provisioned pool - ARM reports `-1` there
    regardless, which is why nulls are not compared.
  EOT
}

variable "high_availability_replica_count" {
  type        = number
  default     = null
  description = "Secondary replicas for high availability. Hyperscale pools only; null elsewhere."
}

# -----------------------------------------------------------------------------
# Optional - resilience
# -----------------------------------------------------------------------------

variable "zone_redundant" {
  type        = bool
  default     = null
  description = <<-EOT
    Spread the pool's replicas across availability zones. Requires a tier that
    HAS replicas - Basic and Standard DTU pools do not, and ARM rejects the
    combination.
  EOT
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

variable "maintenance_configuration_resource_id" {
  type        = string
  default     = null
  description = "Maintenance window configuration ID. Null leaves the pool on the default window, which Azure may apply at any time."
}

# -----------------------------------------------------------------------------
# Optional - licensing and enclave
# -----------------------------------------------------------------------------

variable "license_type" {
  type        = string
  default     = null
  description = "`LicenseIncluded` to pay for the SQL licence, or `BasePrice` to claim Azure Hybrid Benefit against one you already own. vCore tiers only."

  validation {
    condition     = var.license_type == null || contains(["BasePrice", "LicenseIncluded"], var.license_type)
    error_message = "license_type must be one of: BasePrice, LicenseIncluded."
  }
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
    Role assignments scoped to the pool, keyed by stable name.

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
    log_categories                           = optional(map(bool), {})
    log_groups                               = optional(map(bool), { allLogs = true })
    metric_categories                        = optional(map(bool), { AllMetrics = true })
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the pool, keyed by stable name.

    Exactly one destination must be set per entry.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan.
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
    - `name`: optional. Defaults to `lock-<pool-name>`.
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
  description = "Tags applied to the elastic pool."
}
