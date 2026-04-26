variable "name" {
  type        = string
  description = "Name of the virtual network link."
  nullable    = false
}

variable "private_dns_zone_resource_id" {
  type        = string
  description = "ARM resource ID of the private DNS zone."
  nullable    = false
}

variable "virtual_network_resource_id" {
  type        = string
  description = "ARM resource ID of the virtual network to link."
  nullable    = false
}

variable "registration_enabled" {
  type        = bool
  default     = false
  description = "Whether auto-registration of VM records is enabled. Only valid for non-privatelink zones."
  nullable    = false
}

variable "resolution_policy" {
  type        = string
  default     = null
  description = "`Default` or `NxDomainRedirect`. Only applicable to privatelink zones. Leave null for non-privatelink zones."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the link."
}
