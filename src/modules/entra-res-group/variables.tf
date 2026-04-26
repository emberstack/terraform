variable "display_name" {
  description = "Display name of the group. 1–256 characters."
  type        = string

  validation {
    condition     = length(var.display_name) > 0 && length(var.display_name) <= 256
    error_message = "display_name must be between 1 and 256 characters."
  }
}

variable "description" {
  description = "Description of the group. Up to 1024 characters."
  type        = string
  default     = null

  validation {
    condition     = var.description == null || length(var.description) <= 1024
    error_message = "description must be 1024 characters or fewer."
  }
}

variable "mail_enabled" {
  description = "Whether the group is mail-enabled. At least one of `mail_enabled` or `security_enabled` must be true."
  type        = bool
  default     = false

  validation {
    condition     = var.mail_enabled || var.security_enabled
    error_message = "At least one of mail_enabled or security_enabled must be true."
  }
}

variable "security_enabled" {
  description = "Whether the group is security-enabled. At least one of `mail_enabled` or `security_enabled` must be true."
  type        = bool
  default     = true
}

variable "mail_nickname" {
  description = "Mail alias of the group. Required when `mail_enabled = true` or `types` includes `\"Unified\"`."
  type        = string
  default     = null
}

variable "assignable_to_role" {
  description = "Whether the group is eligible to receive Entra directory roles. Immutable after creation."
  type        = bool
  default     = false
}

variable "prevent_duplicate_names" {
  description = "If true, creation fails when a group with the same `display_name` already exists. Create-time check only."
  type        = bool
  default     = false
}

variable "visibility" {
  description = "Visibility of the group. One of: Private, Public, HiddenMembership."
  type        = string
  default     = null

  validation {
    condition     = var.visibility == null || contains(["Private", "Public", "HiddenMembership"], var.visibility)
    error_message = "visibility must be one of: Private, Public, HiddenMembership."
  }
}

variable "types" {
  description = "Group types. Use `[\"Unified\"]` for M365 groups."
  type        = set(string)
  default     = []
}

variable "behaviors" {
  description = "Group behaviors. e.g. `AllowOnlyMembersToPost`, `HideGroupInOutlook`."
  type        = set(string)
  default     = []
}

variable "administrative_unit_ids" {
  description = <<-EOT
    Object IDs of administrative units the group should belong to.

    When non-empty, the group is created atomically in the scope of the first
    AU and added to the others in a single Graph call (no orphan window).
    When unset/empty, the group is created at tenant root.

    ⚠️ Do NOT also manage the same AU memberships via
    `azuread_administrative_unit_member` or `azuread_administrative_unit.members`
    — that produces a persistent diff. Pick one source of truth.
  EOT

  type    = list(string)
  default = []

  validation {
    condition = alltrue([
      for v in var.administrative_unit_ids :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v))
    ])
    error_message = "Each value in administrative_unit_ids must be a valid Entra object ID (UUID)."
  }
}

variable "dynamic_membership" {
  description = "Dynamic membership rule. When set, members are managed by the rule and `members` must be empty."
  type = object({
    enabled = bool
    rule    = string
  })
  default = null
}

variable "owners" {
  description = <<-EOT
    Owners of the group. **Required, must contain ≥1 entry.**

    Map of `<stable-key> => <owner-id>` where `<owner-id>` is **either** a
    valid Entra object ID (UUID) **or** a user principal name (UPN). UPN
    values are resolved via Graph at plan time. Auto-detected by format.

    Examples:
      owners = {
        alice = "11111111-1111-1111-1111-111111111111"  # object_id
        bob   = "bob@example.com"                       # UPN — looked up via Graph
      }

    Why required: groups must always have ≥1 owner. If unset, the
    `azuread_group` provider auto-assigns the deploying principal as owner —
    a footgun in CI/prod (deployer leaves → orphaned owner).

    UPN-based entries require the deploying principal to have at least
    `User.Read.All` Graph permission.
  EOT

  type = map(string)

  validation {
    condition     = length(var.owners) > 0
    error_message = "owners must contain at least one entry."
  }

  validation {
    condition = alltrue([
      for k, v in var.owners :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each value in owners must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }
}

variable "members" {
  description = <<-EOT
    Members of the group.

    Map of `<stable-key> => <member-id>` where `<member-id>` is **either**
    a valid Entra object ID (UUID) **or** a user principal name (UPN).
    UPN values are resolved via Graph at plan time. Auto-detected by format.

    Examples:
      members = {
        alice = "11111111-1111-1111-1111-111111111111"  # object_id
        bob   = "bob@example.com"                       # UPN — looked up via Graph
      }

    Cannot be used together with `dynamic_membership` — the rule manages
    members in that case.

    UPN-based entries require the deploying principal to have at least
    `User.Read.All` Graph permission.
  EOT

  type    = map(string)
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.members :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each value in members must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }

  validation {
    condition     = var.dynamic_membership == null || length(var.members) == 0
    error_message = "members cannot be used when dynamic_membership is set; the membership is managed by the dynamic membership rule."
  }
}
