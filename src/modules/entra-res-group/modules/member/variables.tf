variable "group_object_id" {
  description = "Object ID of the group to add members to."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.group_object_id))
    error_message = "group_object_id must be a valid Entra object ID (UUID)."
  }
}

variable "members" {
  description = <<-EOT
    Map of members to add. The key is a stable identifier (used as the
    `for_each` key); the value is **either** a member's Entra object ID
    (UUID) **or** a user principal name (UPN). Auto-detected by format.

    Examples:
      members = {
        alice = "11111111-1111-1111-1111-111111111111"  # object_id
        bob   = "bob@example.com"                       # UPN — looked up via Graph
      }

    UPN-based entries require the deploying principal to have at least
    `User.Read.All` Graph permission (or be a directory user, which has
    user-read by default).

    Member **values** must be known at plan time. The UPN lookup partitions this
    map by value, so passing a value that comes from another resource makes the
    partition unknown and Terraform rejects the data source's `for_each` with
    "Invalid for_each argument". Map *keys* may be anything static — it is only
    the values that must resolve during plan. When a member is produced by
    another resource, pass its object ID rather than a UPN.
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
}
