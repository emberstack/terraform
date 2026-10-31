# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Network manager name."
  nullable    = false

  # The pattern ARM's own schema publishes for networkManagers: 1-64 characters
  # of alphanumerics, underscores, periods and hyphens, starting alphanumeric and
  # ending alphanumeric or underscore.
  validation {
    condition     = can(regex("^[0-9a-zA-Z]([0-9a-zA-Z_.-]{0,62}[0-9a-zA-Z_])?$", var.name))
    error_message = "name must be 1-64 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the network manager will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the network manager. Its scope can still cover virtual networks in any region."
  nullable    = false
}

variable "network_manager_scope" {
  type = object({
    management_group_ids = optional(list(string), [])
    subscription_ids     = optional(list(string), [])
  })
  description = <<-EOT
    The management groups and subscriptions whose virtual networks the manager can govern. At
    least one entry is required across the two lists.

    - `management_group_ids`: `/providers/Microsoft.Management/managementGroups/<id>`.
    - `subscription_ids`: `/subscriptions/<guid>` — the full resource ID, not the bare GUID.

    Mirrors AVM's `network_manager_scope`.
  EOT
  nullable    = false

  validation {
    condition     = length(var.network_manager_scope.management_group_ids) + length(var.network_manager_scope.subscription_ids) > 0
    error_message = "network_manager_scope needs at least one management group or subscription."
  }

  validation {
    condition = alltrue([
      for id in var.network_manager_scope.subscription_ids :
      can(regex("^/subscriptions/[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Each network_manager_scope.subscription_ids entry must be a subscription resource ID, e.g. /subscriptions/00000000-0000-0000-0000-000000000000."
  }

  validation {
    condition = alltrue([
      for id in var.network_manager_scope.management_group_ids :
      can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/[^/]+$", id))
    ])
    error_message = "Each network_manager_scope.management_group_ids entry must be a management group resource ID, e.g. /providers/Microsoft.Management/managementGroups/<id>."
  }
}

variable "network_manager_scope_accesses" {
  type        = list(string)
  description = "Features the manager may deploy into its scope: any of `Connectivity`, `Routing`, `SecurityAdmin` and `SecurityUser`. An empty list leaves a manager that holds IP address pools and verifier workspaces only. Sent in the order given — ARM echoes it back that way. Mirrors AVM's `network_manager_scope_accesses`."
  nullable    = false

  validation {
    condition     = alltrue([for access in var.network_manager_scope_accesses : contains(["Connectivity", "Routing", "SecurityAdmin", "SecurityUser"], access)])
    error_message = "network_manager_scope_accesses may only contain Connectivity, Routing, SecurityAdmin and SecurityUser."
  }

  validation {
    condition     = length(distinct(var.network_manager_scope_accesses)) == length(var.network_manager_scope_accesses)
    error_message = "network_manager_scope_accesses must not repeat an entry."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "description" {
  type        = string
  default     = null
  description = "Description of the network manager."
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
    Map of network-manager-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Network Contributor`), resolved by a subscription-scope lookup.

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

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the network manager."
}
