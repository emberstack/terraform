# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "subnet_network_security_group_associations" {
  type = map(object({
    subnet_resource_id                 = string
    network_security_group_resource_id = string
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
    Map of subnet → network-security-group associations, keyed by a stable identifier.

    Each entry names its own NSG, so one call can associate several NSGs with several
    subnets. That covers the plain case of one shared NSG across many subnets (repeat the
    same `network_security_group_resource_id`) as well as the dedicated-NSG-per-subnet
    shape that delegated services such as Azure SQL Managed Instance require.

    The map key is the `for_each` address and the output key — pick stable keys.

    Fields:
    - `subnet_resource_id` (required) — ARM resource ID of the existing subnet to write. Must be distinct across entries.
    - `network_security_group_resource_id` (required) — ARM resource ID of the NSG to associate.
  EOT

  validation {
    condition     = alltrue([for k, v in var.subnet_network_security_group_associations : can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/virtualnetworks/[^/]+/subnets/[^/]+$", v.subnet_resource_id))])
    error_message = "Each entry's `subnet_resource_id` must be an ARM resource ID of a subnet, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }

  validation {
    condition     = alltrue([for k, v in var.subnet_network_security_group_associations : can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/networksecuritygroups/[^/]+$", v.network_security_group_resource_id))])
    error_message = "Each entry's `network_security_group_resource_id` must be an ARM resource ID of a network security group, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/networkSecurityGroups/<nsg>."
  }

  # A subnet carries at most one NSG, so two entries naming the same subnet do
  # not merge — they both write and the survivor depends on apply order.
  # Compared case-insensitively because ARM resource IDs are, and the same
  # subnet can reach two entries with different casing.
  validation {
    condition     = length(distinct([for k, v in var.subnet_network_security_group_associations : lower(v.subnet_resource_id)])) == length(var.subnet_network_security_group_associations)
    error_message = "Each entry must target a distinct `subnet_resource_id`: a subnet holds at most one network security group, so two entries naming the same subnet would race and the surviving association would depend on apply order."
  }
}

# -----------------------------------------------------------------------------
# Optional — behaviour
# -----------------------------------------------------------------------------

variable "retry" {
  type = object({
    error_message_regex  = list(string)
    interval_seconds     = optional(number)
    max_interval_seconds = optional(number)
    multiplier           = optional(number)
    randomization_factor = optional(number)
  })
  description = "Retry the write when the error message matches one of `error_message_regex` — ARM serialises writes against a virtual network, so entries targeting subnets of the same vnet can collide with an operation already in progress. Bounded by the Terraform context deadline. Null disables it."
  default     = null

  validation {
    condition     = var.retry == null || length(try(var.retry.error_message_regex, [])) > 0
    error_message = "retry.error_message_regex must contain at least one pattern; leave retry null to disable retrying."
  }

  # regexall, not regex: regex() errors when the pattern does not match, so
  # can(regex(p, "")) would reject every pattern not present in the empty
  # string — which is all of them.
  validation {
    condition     = var.retry == null || alltrue([for pattern in try(var.retry.error_message_regex, []) : can(regexall(pattern, ""))])
    error_message = "every retry.error_message_regex entry must be a valid regular expression."
  }
}
