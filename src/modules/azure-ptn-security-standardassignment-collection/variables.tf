variable "exemptions" {
  type = map(object({
    scope                = string
    assigned_standard_id = string
    assessment_key       = string
    exemption_category   = string
    name                 = optional(string, null)
    display_name         = optional(string, null)
    description          = optional(string, null)
    expires_on           = optional(string, null)
  }))
  description = <<-EOT
    Defender for Cloud recommendation exemptions, keyed by a stable identifier.
    Each entry maps onto one `azure-res-security-standardassignment`, which
    validates it.

    Required fields per entry:
    - `scope`                : ARM ID of the management group, subscription,
                               resource group or resource.
    - `assigned_standard_id` : resource ID of the security standard carrying
                               the recommendation.
    - `assessment_key`       : key of the recommendation to exempt.
    - `exemption_category`   : `waiver` or `mitigated` (lower case).

    Optional fields per entry:
    - `name`         : GUID name; null derives a stable one. Set it to adopt an
                       existing exemption by import.
    - `display_name` : portal display name.
    - `description`  : the justification.
    - `expires_on`   : RFC 3339 expiry timestamp.
  EOT
  nullable    = false
}
