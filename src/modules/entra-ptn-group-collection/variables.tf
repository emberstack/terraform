variable "groups" {
  description = <<-EOT
    Map of Entra group configurations. Each entry creates one group via the
    singular `entra-res-group` resource module.

    The key in the map is the stable identifier for the group instance — used
    as Terraform's `for_each` address — and is also the key under which the
    group appears in this module's `groups` output. Choose stable, meaningful
    keys (e.g., `ops_admins`, `engineering_readers`) so removing one entry
    doesn't shift the addresses of the others.

    Each entry's value mirrors the input shape of `entra-res-group`.
    See that module's README for field semantics, validations, and behavior.

    Required per entry:
      - display_name
      - owners  (map of <stable-key> => <object-id>; must contain ≥1 entry)

    Common optional fields:
      - description, mail_enabled, security_enabled, mail_nickname,
        assignable_to_role, prevent_duplicate_names, visibility, types,
        behaviors, administrative_unit_ids, dynamic_membership, members
  EOT

  type = map(object({
    display_name            = string
    description             = optional(string)
    mail_enabled            = optional(bool, false)
    security_enabled        = optional(bool, true)
    mail_nickname           = optional(string)
    assignable_to_role      = optional(bool, false)
    prevent_duplicate_names = optional(bool, false)
    visibility              = optional(string)
    types                   = optional(set(string), [])
    behaviors               = optional(set(string), [])
    administrative_unit_ids = optional(list(string), [])

    dynamic_membership = optional(object({
      enabled = bool
      rule    = string
    }))

    owners  = map(string)
    members = optional(map(string), {})
  }))

  default = {}
}
