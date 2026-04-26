variable "group_memberships" {
  description = <<-EOT
    Map of Entra group memberships. Each entry adds one principal to one
    group via `azuread_group_member`.

    The key is a stable identifier (used as the `for_each` address); choose
    meaningful keys so removing one entry doesn't shift the addresses of
    the others.

    Fields:
      - group_object_id: Object ID (UUID) of the group to add the member to.
      - member:          Either an Entra object ID (UUID) of any principal —
                         user, group, service principal — **or** a user
                         principal name (UPN). UPN values are resolved via
                         the `azuread_user` data source. Auto-detected by
                         format. UPNs only resolve to **users**; groups and
                         service principals must be passed by object ID.

    `member` values must be known at plan time. The UPN lookup filters this map
    by value, so a `member` sourced from another resource makes the filtered set
    unknown and Terraform rejects the data source's `for_each` with "Invalid
    for_each argument". `group_object_id` is not affected — it may be computed.

    Example:
      group_memberships = {
        gha_in_operators = {
          group_object_id = "11111111-1111-1111-1111-111111111111"
          member          = "22222222-2222-2222-2222-222222222222"
        }
        alice_in_operators = {
          group_object_id = "11111111-1111-1111-1111-111111111111"
          member          = "alice@example.com"
        }
      }
  EOT

  type = map(object({
    group_object_id = string
    member          = string
  }))

  default = {}

  validation {
    condition = alltrue([
      for k, v in var.group_memberships :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.group_object_id))
    ])
    error_message = "Each group_memberships[*].group_object_id must be a valid Entra object ID (UUID)."
  }

  validation {
    condition = alltrue([
      for k, v in var.group_memberships :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v.member)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v.member))
    ])
    error_message = "Each group_memberships[*].member must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }
}
