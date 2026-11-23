# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Database name, unique within the managed instance."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 128 && !can(regex("[<>*%&:\\\\/?]", var.name)) && !can(regex("[. ]$", var.name))
    error_message = "name must be 1-128 characters, must not contain < > * % & : \\ / ?, and must not end with a period or space."
  }
}

variable "managed_instance_resource_id" {
  type        = string
  description = "ARM resource ID of the SQL managed instance. Used directly as the database's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Sql/managedInstances/[^/]+$", var.managed_instance_resource_id))
    error_message = "managed_instance_resource_id must be a Microsoft.Sql/managedInstances resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region. Must match the managed instance's region."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional - engine
# -----------------------------------------------------------------------------

variable "collation" {
  type        = string
  default     = null
  description = <<-EOT
    Database collation, e.g. `SQL_Latin1_General_CP1_CI_AS`. Null takes the
    instance's default.

    Fixed at creation - ARM rejects a change rather than applying it.
  EOT
}

variable "catalog_collation" {
  type        = string
  default     = null
  description = "Collation of the metadata catalog: `DATABASE_DEFAULT` or `SQL_Latin1_General_CP1_CI_AS`. Fixed at creation."

  validation {
    condition     = var.catalog_collation == null || contains(["DATABASE_DEFAULT", "SQL_Latin1_General_CP1_CI_AS"], var.catalog_collation)
    error_message = "catalog_collation must be one of: DATABASE_DEFAULT, SQL_Latin1_General_CP1_CI_AS."
  }
}

variable "ledger_enabled" {
  type        = bool
  default     = null
  description = "Make every table in the database a ledger table. Fixed at creation."
}

# -----------------------------------------------------------------------------
# Optional - backup retention
# -----------------------------------------------------------------------------

variable "short_term_retention" {
  type = object({
    retention_days = number
  })
  default     = null
  description = <<-EOT
    Point-in-time restore window. Null leaves Azure's default of 7 days.

    - `retention_days`: 1-35.

    The differential backup interval is not configurable on a managed instance.
    PITR backups do not survive deletion of the instance - use
    `long_term_retention` for backups that outlive it.
  EOT

  validation {
    condition     = var.short_term_retention == null || (try(var.short_term_retention.retention_days, 0) >= 1 && try(var.short_term_retention.retention_days, 0) <= 35)
    error_message = "short_term_retention.retention_days must be between 1 and 35."
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
    REQUIRED whenever `yearly_retention` is set.

    LTR is the ONLY backup class that survives deletion of the managed instance.
    Changing the policy applies to future backups only - existing LTR backups
    keep the retention they were taken with.
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
    inside the database - that is a SQL-level grant.

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
    metric_categories                        = optional(map(bool), {})
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
    - `name`: optional. Defaults to `lock-<database-name>`.

    A `ReadOnly` lock also blocks the retention policy updates above.
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
