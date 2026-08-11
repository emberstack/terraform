# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Exemption name. 1–64 chars."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "name must be between 1 and 64 characters."
  }
}

variable "scope" {
  type        = string
  description = <<-EOT
    ARM resource ID where the exemption applies. Detected formats:

    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`
    - Resource group:   `/subscriptions/<sub>/resourceGroups/<rg>`
    - Resource:         `/subscriptions/<sub>/resourceGroups/<rg>/providers/<...>`

    Segment names are matched case-insensitively, because ARM treats them that
    way (`/RESOURCEGROUPS/` is a valid ID Azure accepts).
  EOT
  nullable    = false

  validation {
    condition = (
      can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+$", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ||
      can(regex("(?i)^/subscriptions/[^/]+(/resourceGroups/[^/]+)?/providers/", var.scope))
    )
    error_message = "scope must be a management group, subscription, resource group, or resource ARM resource ID."
  }
}

variable "policy_assignment_id" {
  type        = string
  description = "ARM resource ID of the policy assignment from which to exempt."
  nullable    = false
}

variable "exemption_category" {
  type        = string
  description = "`Waiver` (accept the deviation) or `Mitigated` (an alternative control compensates for the deviation)."
  nullable    = false

  validation {
    condition     = contains(["Waiver", "Mitigated"], var.exemption_category)
    error_message = "exemption_category must be 'Waiver' or 'Mitigated'."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "display_name" {
  type        = string
  default     = null
  description = "Portal display name."
}

variable "description" {
  type        = string
  default     = null
  description = "Long-form description."
}

variable "expires_on" {
  type        = string
  default     = null
  description = "Expiration timestamp in RFC 3339 (e.g. `2026-12-31T23:59:59Z`). After this time, the exemption is no longer applied."
}

variable "policy_definition_reference_ids" {
  type        = list(string)
  default     = null
  description = <<-EOT
    Reference IDs (within an initiative) to scope the exemption to a subset of
    its policies. Leave null to exempt all policies the assignment applies.
  EOT
}

variable "metadata" {
  type        = any
  default     = {}
  description = "Exemption metadata as an HCL object. Common keys: `requestedBy`, `approvedBy`, `ticket`, etc."
  nullable    = false
}
