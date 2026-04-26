variable "exemptions" {
  type = map(object({
    name                            = string
    scope                           = string
    policy_assignment_id            = string
    exemption_category              = string
    display_name                    = optional(string, null)
    description                     = optional(string, null)
    expires_on                      = optional(string, null)
    policy_definition_reference_ids = optional(list(string), null)
    metadata                        = optional(any, {})
  }))
  description = <<-EOT
    Map of policy exemptions, keyed by stable name. Each entry maps onto one
    `azure-res-policy-exemption` invocation; the `scope` field auto-routes to
    the right resource type (subscription / resource group / resource /
    management group).

    Required fields per entry:
    - `name`                  : exemption resource name (1–64 chars).
    - `scope`                 : ARM ID of the scope.
    - `policy_assignment_id`  : ARM ID of the assignment to exempt from.
    - `exemption_category`    : `Waiver` or `Mitigated`.

    Optional fields per entry:
    - `display_name`                    : portal display name.
    - `description`                     : long-form description.
    - `expires_on`                      : RFC 3339 expiry timestamp.
    - `policy_definition_reference_ids` : restrict to specific policies inside an initiative.
    - `metadata`                        : free-form metadata as an HCL object.
  EOT
  nullable    = false
}
