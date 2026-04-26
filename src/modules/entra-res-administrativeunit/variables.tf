variable "display_name" {
  description = "Display name of the administrative unit. 1–256 characters."
  type        = string

  validation {
    condition     = length(var.display_name) > 0 && length(var.display_name) <= 256
    error_message = "display_name must be between 1 and 256 characters."
  }
}

variable "description" {
  description = "Description of the administrative unit. Up to 1024 characters."
  type        = string
  default     = null

  validation {
    condition     = var.description == null || length(var.description) <= 1024
    error_message = "description must be 1024 characters or fewer."
  }
}

variable "hidden_membership_enabled" {
  description = "Whether members of this administrative unit are hidden from non-members."
  type        = bool
  default     = false
}

variable "prevent_duplicate_names" {
  description = "If true, creation fails when an AU with the same `display_name` already exists. Create-time check only."
  type        = bool
  default     = false
}

variable "members" {
  description = <<-EOT
    Members of the administrative unit.

    Map of `<stable-key> => <member-object-id>`. The key is used as the
    `for_each` address (so removing one entry does not churn the others).
    Object IDs must be valid Entra UUIDs.
  EOT

  type    = map(string)
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.members :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v))
    ])
    error_message = "Each value in members must be a valid Entra object ID (UUID)."
  }
}

variable "role_assignments" {
  description = <<-EOT
    Map of AU-scoped Entra directory role assignments.

    Each entry creates an `azuread_directory_role_assignment` with
    `directory_scope_id = /administrativeUnits/<this-au-object-id>`.

    Fields:
      - role_id:    Object ID of an *activated* Entra directory role
                    (use `azuread_directory_role` to activate from a
                    template, or look up via data source).
      - principal:  **Either** a valid Entra object ID (UUID) **or** a user
                    principal name (UPN). UPN values are resolved via Graph
                    at plan time. Auto-detected by format.

    Examples:
      role_assignments = {
        ops_user_admin = {
          role_id   = azuread_directory_role.user_administrator.object_id
          principal = "11111111-1111-1111-1111-111111111111" # object_id
        }
        alice_user_admin = {
          role_id   = azuread_directory_role.user_administrator.object_id
          principal = "alice@example.com"                    # UPN — looked up
        }
      }

    UPN-based entries require the deploying principal to have at least
    `User.Read.All` Graph permission. UPNs only resolve to **users**; groups
    and service principals must be passed by object ID.
  EOT

  type = map(object({
    role_id   = string
    principal = string
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, v in var.role_assignments :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.role_id))
    ])
    error_message = "Each role_assignments[*].role_id must be a valid Entra object ID (UUID)."
  }

  validation {
    condition = alltrue([
      for k, v in var.role_assignments :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.principal)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v.principal))
    ])
    error_message = "Each role_assignments[*].principal must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }
}
