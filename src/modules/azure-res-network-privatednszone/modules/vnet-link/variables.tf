# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the virtual network link."
  nullable    = false
}

variable "private_dns_zone_resource_id" {
  type        = string
  description = "ARM resource ID of the private DNS zone. Used directly as the link's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/privatednszones/[^/]+$", var.private_dns_zone_resource_id))
    error_message = "private_dns_zone_resource_id must be an ARM resource ID of an Azure private DNS zone."
  }
}

variable "virtual_network_resource_id" {
  type        = string
  description = "ARM resource ID of the virtual network to link."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — behaviour
# -----------------------------------------------------------------------------

variable "registration_enabled" {
  type        = bool
  default     = false
  description = "Whether auto-registration of VM records is enabled. Only valid for non-privatelink zones."
  nullable    = false
}

variable "resolution_policy" {
  type        = string
  default     = null
  description = "`Default` or `NxDomainRedirect`. Only applicable to privatelink zones. Leave null for non-privatelink zones — the property is then omitted from the request entirely."

  validation {
    condition     = var.resolution_policy == null || contains(["Default", "NxDomainRedirect"], var.resolution_policy)
    error_message = "resolution_policy must be null, `Default`, or `NxDomainRedirect`."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the link."
}
