# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the Fabric capacity. Lowercase letters and digits only — the capacities API rejects hyphens and uppercase."
  nullable    = false

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,62}$", var.name))
    error_message = "name must be 3-63 characters of lowercase letters or digits and start with a letter."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the capacity in. Resolved against the provider's subscription."
  nullable    = false
}

variable "location" {
  type        = string
  description = "Azure region for the capacity."
  nullable    = false
}

variable "sku_name" {
  type        = string
  description = "Fabric F SKU. The tier is always `Fabric` and is not configurable."
  nullable    = false

  validation {
    condition     = can(regex("^F(2|4|8|16|32|64|128|256|512|1024|2048)$", var.sku_name))
    error_message = "sku_name must be a Fabric F SKU: F2, F4, F8, F16, F32, F64, F128, F256, F512, F1024 or F2048."
  }
}

variable "administration_members" {
  type        = set(string)
  description = <<-EOT
    Capacity administrators, as Entra user principal names or service-principal object IDs.
    At least one is required — the capacities API rejects a create with an empty set.

    Fabric does not accept groups here, only individual principals.

    Declared as a set because ARM treats it as one: the order supplied is neither preserved
    nor returned, and this module does not compare against ARM's ordering. See the note in
    the README.
  EOT
  nullable    = false

  validation {
    condition     = length(var.administration_members) > 0
    error_message = "administration_members must contain at least one member."
  }

  validation {
    condition = alltrue([
      for member in var.administration_members :
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", member)) ||
      can(regex("(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", member))
    ])
    error_message = "Each administration_members entry must be a user principal name or a service-principal object ID (GUID)."
  }
}

# -----------------------------------------------------------------------------
# Optional
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
    Map of capacity-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Contributor`), resolved by a subscription-scope lookup.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is generated — unless you
    are adopting an assignment that already exists, where the existing GUID must be supplied to avoid a
    destroy-and-recreate.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal or a managed
    identity, so ARM skips the directory lookup that fails on a principal created moments earlier.

    Do not edit `principal_id` or `role_definition_id_or_name` on an existing key — ARM rejects the update.
    Add a new key and remove the old one instead.

    An Azure RBAC role is not the same thing as capacity administration: `administration_members` governs
    who administers the capacity inside Fabric, this governs the ARM control plane.

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
  description = "Tags applied to the capacity."
}
