# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Workspace name."
  nullable    = false

  # ARM schema: 4-63 characters, alphanumerics and hyphens, starting and ending
  # alphanumeric.
  validation {
    condition     = can(regex("^[A-Za-z0-9][A-Za-z0-9-]{2,61}[A-Za-z0-9]$", var.name))
    error_message = "name must be 4-63 characters of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the workspace will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the workspace and its transformation DCR."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — pricing, retention and ingestion
# -----------------------------------------------------------------------------

variable "sku" {
  type        = string
  default     = "PerGB2018"
  description = "Pricing tier. `PerGB2018` is pay-as-you-go; `CapacityReservation` takes a commitment tier set outside this module."
  nullable    = false

  validation {
    condition     = contains(["CapacityReservation", "Free", "LACluster", "PerGB2018", "PerNode", "Premium", "Standalone", "Standard"], var.sku)
    error_message = "sku must be one of: CapacityReservation, Free, LACluster, PerGB2018, PerNode, Premium, Standalone, Standard."
  }
}

variable "retention_in_days" {
  type        = number
  default     = 30
  description = "Interactive retention in days: 30-730, or 7 on the Free tier. Azure's default is 30."
  nullable    = false

  validation {
    condition = (
      floor(var.retention_in_days) == var.retention_in_days &&
      (var.sku == "Free" ? var.retention_in_days == 7 : var.retention_in_days >= 30 && var.retention_in_days <= 730)
    )
    error_message = "retention_in_days must be a whole number from 30 to 730, or 7 on the Free tier."
  }
}

variable "daily_quota_gb" {
  type        = number
  default     = -1
  description = <<-EOT
    Daily ingestion cap in GB, or -1 for no cap.

    When the cap is reached, ingestion stops for EVERY table in the workspace until the
    next reset — not only for the noisy one.
  EOT
  nullable    = false

  validation {
    condition     = var.daily_quota_gb == -1 || var.daily_quota_gb > 0
    error_message = "daily_quota_gb must be -1 (no cap) or greater than 0."
  }
}

variable "cmk_for_query_forced" {
  type        = bool
  default     = false
  description = "Require saved queries and alert query results to use customer-managed storage (`forceCmkForQuery`)."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — access
# -----------------------------------------------------------------------------

variable "public_network_access_for_ingestion" {
  type        = string
  default     = "Enabled"
  description = "Public network access for ingestion: Enabled, Disabled or SecuredByPerimeter."
  nullable    = false

  validation {
    condition     = contains(["Disabled", "Enabled", "SecuredByPerimeter"], var.public_network_access_for_ingestion)
    error_message = "public_network_access_for_ingestion must be Enabled, Disabled or SecuredByPerimeter."
  }
}

variable "public_network_access_for_query" {
  type        = string
  default     = "Enabled"
  description = "Public network access for queries: Enabled, Disabled or SecuredByPerimeter."
  nullable    = false

  validation {
    condition     = contains(["Disabled", "Enabled", "SecuredByPerimeter"], var.public_network_access_for_query)
    error_message = "public_network_access_for_query must be Enabled, Disabled or SecuredByPerimeter."
  }
}

variable "local_authentication_enabled" {
  type        = bool
  default     = true
  description = "Allow non-Entra authentication (the workspace shared keys). Azure's default is true."
  nullable    = false
}

variable "allow_resource_only_permissions" {
  type        = bool
  default     = true
  description = "Let users read the logs of resources they have access to without workspace permissions (resource-context access). Azure's default is true."
  nullable    = false
}

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    Managed identity for the workspace — needed for linked storage accounts.

    - `system_assigned`: enable a system-assigned identity.
    - `user_assigned_resource_ids`: user-assigned identities to attach.

    A workspace carries one identity type, so set one or the other.
  EOT
  nullable    = false

  validation {
    condition     = !(var.managed_identities.system_assigned && length(var.managed_identities.user_assigned_resource_ids) > 0)
    error_message = "managed_identities: a workspace takes a system-assigned OR user-assigned identity, not both."
  }
}

# -----------------------------------------------------------------------------
# Optional — children
# -----------------------------------------------------------------------------

variable "workspace_transforms" {
  type = object({
    name        = string
    description = optional(string, "Ingestion-time transformations for workspace tables")
    table_transforms = map(object({
      transform_kql = string
      description   = optional(string)
    }))
  })
  default     = null
  description = <<-EOT
    Workspace transformation DCR (`kind = WorkspaceTransforms`), created and linked as the
    workspace's default DCR. Keyed by table name (e.g. `AppMetrics`); `transform_kql` runs at
    ingestion and must start with `source`. A table's `description` documents the transform
    in code only — DCR data flows have no description field.

    It applies only to data that does not already arrive through a DCR of its own
    (diagnostic settings and Application Insights, for example).
  EOT

  validation {
    condition     = var.workspace_transforms == null || can(regex("^[A-Za-z0-9][A-Za-z0-9._-]{0,62}[A-Za-z0-9_]$", var.workspace_transforms.name))
    error_message = "workspace_transforms.name must be 2-64 characters of letters, digits, periods, underscores and hyphens, starting with a letter or digit."
  }

  validation {
    condition     = var.workspace_transforms == null || length(var.workspace_transforms.table_transforms) > 0
    error_message = "workspace_transforms.table_transforms must name at least one table."
  }

  validation {
    condition = var.workspace_transforms == null || alltrue([
      for transform in values(var.workspace_transforms.table_transforms) : startswith(trimspace(transform.transform_kql), "source")
    ])
    error_message = "workspace_transforms: every transform_kql must start with `source`."
  }
}

variable "sentinel_onboarding_enabled" {
  type        = bool
  default     = false
  description = "Onboard the workspace to Microsoft Sentinel."
  nullable    = false
}

variable "linked_storage_accounts" {
  type        = map(list(string))
  default     = {}
  description = <<-EOT
    Storage accounts linked to the workspace, keyed by data source type: `Alerts` (alert query
    results), `AzureWatson`, `CustomLogs`, `Ingestion` or `Query` (saved queries). Each value
    lists storage account resource IDs. The workspace needs a managed identity with access to
    the accounts.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for type in keys(var.linked_storage_accounts) : contains(["Alerts", "AzureWatson", "CustomLogs", "Ingestion", "Query"], type)])
    error_message = "linked_storage_accounts keys must be from: Alerts, AzureWatson, CustomLogs, Ingestion, Query."
  }

  validation {
    condition     = alltrue([for ids in values(var.linked_storage_accounts) : length(ids) > 0 && alltrue([for id in ids : can(regex("(?i)/providers/Microsoft\\.Storage/storageAccounts/[^/]+$", id))])])
    error_message = "linked_storage_accounts values must be non-empty lists of storage account resource IDs."
  }
}

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
    Map of workspace-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Log Analytics Reader`), resolved by a subscription-scope lookup.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is generated — unless you
    are adopting an assignment that already exists, where the existing GUID must be supplied to avoid a
    destroy-and-recreate.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal or a managed
    identity, so ARM skips the directory lookup that fails on a principal created moments earlier.

    Do not edit `principal_id` or `role_definition_id_or_name` on an existing key — ARM rejects the update.
    Add a new key and remove the old one instead.

    Mirrors AVM's standard `role_assignments` interface block.
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
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the workspace and its transformation DCR."
}
