# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "scope" {
  type        = string
  description = <<-EOT
    ARM resource ID where the exemption applies. Detected formats:

    - Management group: `/providers/Microsoft.Management/managementGroups/<mg>`
    - Subscription:     `/subscriptions/<sub>`
    - Resource group:   `/subscriptions/<sub>/resourceGroups/<rg>`
    - Resource:         `/subscriptions/<sub>/resourceGroups/<rg>/providers/<...>`

    Segment names are matched case-insensitively, because ARM treats them that
    way. Changing the scope recreates the exemption.
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

variable "assigned_standard_id" {
  type        = string
  description = <<-EOT
    Resource ID of the security standard that carries the recommendation, as
    `.../providers/Microsoft.Security/securityStandards/<id>`. A built-in
    standard is addressed at tenant level
    (`/providers/Microsoft.Security/securityStandards/<id>`).
  EOT
  nullable    = false

  validation {
    condition     = can(regex("(?i)/providers/Microsoft\\.Security/securityStandards/[^/]+$", var.assigned_standard_id))
    error_message = "assigned_standard_id must be a Microsoft.Security/securityStandards resource ID."
  }
}

variable "assessment_key" {
  type        = string
  description = "Key of the recommendation to exempt — the assessment name Defender for Cloud shows for it, not the ID of one assessed resource."
  nullable    = false

  validation {
    condition     = length(trimspace(var.assessment_key)) > 0
    error_message = "assessment_key must not be empty."
  }
}

variable "exemption_category" {
  type        = string
  description = "`waiver` (the deviation is accepted) or `mitigated` (another control compensates for it). Lower case, as the API defines them."
  nullable    = false

  validation {
    condition     = contains(["waiver", "mitigated"], var.exemption_category)
    error_message = "exemption_category must be 'waiver' or 'mitigated' (lower case)."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  default     = null
  description = "Exemption name, a GUID. Null derives a stable one from the scope, standard and assessment key; set it to adopt an existing exemption by import."

  validation {
    condition     = var.name == null || can(regex("^[{]?[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}[}]?$", coalesce(var.name, "-")))
    error_message = "name must be a GUID."
  }
}

variable "display_name" {
  type        = string
  default     = null
  description = "Portal display name."
}

variable "description" {
  type        = string
  default     = null
  description = "Long-form description — the justification an auditor reads."
}

variable "expires_on" {
  type        = string
  default     = null
  description = "Expiration timestamp in RFC 3339 (e.g. `2026-12-31T23:59:59Z`). After it, the exemption no longer applies."

  validation {
    condition     = var.expires_on == null || can(timeadd(coalesce(var.expires_on, "-"), "0s"))
    error_message = "expires_on must be an RFC 3339 timestamp, e.g. 2026-12-31T23:59:59Z."
  }
}
