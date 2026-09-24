# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "route_table_resource_id" {
  type        = string
  description = "ARM resource ID of the existing route table. Used directly as each route's `parent_id`, and as the lock key that serialises writes into it."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/routetables/[^/]+$", var.route_table_resource_id))
    error_message = "route_table_resource_id must be an ARM resource ID of a route table, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/routeTables/<table>."
  }
}

# -----------------------------------------------------------------------------
# Optional — routes
# -----------------------------------------------------------------------------

variable "routes" {
  type = map(object({
    name                   = string
    address_prefix         = string
    next_hop_type          = string
    next_hop_in_ip_address = optional(string)
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
    Map of routes to create in the route table, keyed by a stable identifier. The object shape
    mirrors the `routes` input of `Azure/avm-res-network-routetable` field for field, so a route
    moves between the two without being rewritten.

    The map key is the `for_each` address and the output key — pick stable keys. The ARM name
    comes from `name`, not from the key.

    Fields:
    - `name` (required) — route name, unique within the table (compared case-insensitively). 1-80 characters: alphanumerics, underscores, periods and hyphens, starting with an alphanumeric and ending with an alphanumeric or underscore.
    - `address_prefix` (required) — destination, as a CIDR (`10.1.0.0/16`) or an Azure service tag (`AzureMonitor`).
    - `next_hop_type` (required) — one of `Internet`, `None`, `VirtualAppliance`, `VirtualNetworkGateway`, `VnetLocal`.
    - `next_hop_in_ip_address` (optional) — IP address packets are forwarded to. Required when `next_hop_type` is `VirtualAppliance`, rejected for every other type.
  EOT

  validation {
    condition     = alltrue([for k, v in var.routes : can(regex("^[A-Za-z0-9]([A-Za-z0-9._-]{0,78}[A-Za-z0-9_])?$", v.name))])
    error_message = "Each route's `name` must be 1-80 characters of alphanumerics, underscores, periods and hyphens, starting with an alphanumeric and ending with an alphanumeric or underscore."
  }

  # ARM names are case-insensitive, so two entries differing only in case would
  # address the same route and overwrite each other on every apply.
  validation {
    condition     = length(distinct([for k, v in var.routes : lower(v.name)])) == length(var.routes)
    error_message = "Route names must be unique within the table, compared case-insensitively."
  }

  # Service tags are not enumerated — the list is long, grows, and differs
  # between clouds — so a prefix without a `/` is only checked for shape.
  validation {
    condition = alltrue([
      for k, v in var.routes : (
        strcontains(v.address_prefix, "/") ? can(cidrhost(v.address_prefix, 0)) : can(regex("^\\S+$", v.address_prefix))
      )
    ])
    error_message = "Each route's `address_prefix` must be a valid CIDR (e.g. 10.1.0.0/16) or a service tag name (e.g. AzureMonitor)."
  }

  # `VirtualApplianceEcmp` (API 2025-07-01 onward) is deliberately absent: it
  # carries its next hops in a separate `nextHop` object this module does not
  # send, so accepting the type would create routes with no next hop.
  validation {
    condition     = alltrue([for k, v in var.routes : contains(["Internet", "None", "VirtualAppliance", "VirtualNetworkGateway", "VnetLocal"], v.next_hop_type)])
    error_message = "Each route's `next_hop_type` must be one of: Internet, None, VirtualAppliance, VirtualNetworkGateway, VnetLocal."
  }

  validation {
    condition     = alltrue([for k, v in var.routes : (v.next_hop_type == "VirtualAppliance") == (v.next_hop_in_ip_address != null)])
    error_message = "`next_hop_in_ip_address` is required when `next_hop_type` is VirtualAppliance, and must be null for every other type."
  }

  # Everything that can fail on a null sits inside `can`, because HCL's `||`
  # does not short-circuit.
  validation {
    condition = alltrue([
      for k, v in var.routes : v.next_hop_in_ip_address == null || can(cidrhost("${v.next_hop_in_ip_address}/${strcontains(v.next_hop_in_ip_address, ":") ? 128 : 32}", 0))
    ])
    error_message = "Each route's `next_hop_in_ip_address` must be a single IPv4 or IPv6 address, without a prefix length."
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
  description = "Retry the write when the error message matches one of `error_message_regex` — for another configuration writing into the same route table at the same time, which the module's own lock cannot see. Bounded by the Terraform context deadline. Null disables it."
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
