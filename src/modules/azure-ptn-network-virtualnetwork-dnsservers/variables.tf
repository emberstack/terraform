variable "virtual_network_resource_id" {
  type        = string
  description = "ARM resource ID of the existing virtual network whose DNS servers will be set."
  nullable    = false

  validation {
    condition     = can(regex("^(?i)/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", var.virtual_network_resource_id))
    error_message = "virtual_network_resource_id must be an ARM resource ID of a virtual network, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<name>."
  }
}

variable "dns_servers" {
  type        = list(string)
  description = "List of DNS server IP addresses. Pass an empty list to revert to Azure-provided DNS."
  nullable    = false
}
