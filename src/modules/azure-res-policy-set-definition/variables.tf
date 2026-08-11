# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the policy set (initiative). 1–64 chars."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "name must be between 1 and 64 characters."
  }
}

variable "display_name" {
  type        = string
  description = "Human-readable display name shown in the portal."
  nullable    = false
}

variable "policy_definition_references" {
  type = map(object({
    policy_definition_id = string
    parameter_values     = optional(any, {})
    policy_group_names   = optional(set(string), null)
  }))
  description = <<-EOT
    Map of policy definitions included in the initiative, keyed by reference ID.

    The key is the `reference_id` (used as a stable handle for exemptions and
    compliance reporting), and `parameter_values` is the per-policy parameter
    binding written as an HCL object — it reaches ARM as a native object, not as
    a JSON-encoded string.

    Example:
    ```
    policy_definition_references = {
      deny_unmanaged_disks = {
        policy_definition_id = module.def_deny_unmanaged_disks.resource_id
        parameter_values = {
          effect = { value = "Deny" }
        }
      }
    }
    ```
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — scope
# -----------------------------------------------------------------------------

variable "management_group_id" {
  type        = string
  default     = null
  description = "ARM resource ID of the management group to scope the initiative to. Leave null to scope to the current subscription."
}

# -----------------------------------------------------------------------------
# Optional — descriptive
# -----------------------------------------------------------------------------

variable "description" {
  type        = string
  default     = null
  description = "Long-form description shown in the portal."
}

variable "parameters" {
  type        = any
  default     = {}
  description = <<-EOT
    Initiative-level parameter declarations as an HCL object. Same shape as a
    policy definition's `parameters`. Empty map (default) means no parameters.
  EOT
  nullable    = false
}

variable "metadata" {
  type        = any
  default     = {}
  description = "Metadata as an HCL object. Common keys: `category`, `version`."
  nullable    = false
}

variable "policy_definition_groups" {
  type = map(object({
    display_name                    = optional(string, null)
    category                        = optional(string, null)
    description                     = optional(string, null)
    additional_metadata_resource_id = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Optional groupings exposed by the initiative, keyed by group name.

    Reference a group from a policy via `policy_group_names = ["my-group"]` on
    the corresponding entry in `policy_definition_references`.
  EOT
  nullable    = false
}
