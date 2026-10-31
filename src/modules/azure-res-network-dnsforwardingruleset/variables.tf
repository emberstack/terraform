# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "DNS forwarding ruleset name."
  nullable    = false

  # Azure's rule for dnsForwardingRulesets: 1-80 characters of alphanumerics,
  # underscores and hyphens, starting and ending alphanumeric (resource-name-rules
  # table, Microsoft.Network).
  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9_-]{0,78}[A-Za-z0-9])?$", var.name))
    error_message = "name must be 1–80 characters of letters, digits, underscores and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the ruleset will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the ruleset. Must be the region of the DNS resolver that owns the outbound endpoints; a ruleset can only be linked to virtual networks in its own region."
  nullable    = false
}

variable "dns_resolver_outbound_endpoint_resource_ids" {
  type        = list(string)
  description = "Resource IDs of the DNS resolver outbound endpoints the ruleset forwards through — one or two, both belonging to the same DNS resolver."
  nullable    = false

  validation {
    condition = alltrue([
      for id in var.dns_resolver_outbound_endpoint_resource_ids :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/dnsResolvers/[^/]+/outboundEndpoints/[^/]+$", id))
    ])
    error_message = "Each dns_resolver_outbound_endpoint_resource_ids entry must be the resource ID of a DNS resolver outbound endpoint, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/dnsResolvers/<resolver>/outboundEndpoints/<endpoint>."
  }

  # Azure DNS Private Resolver limits: up to 2 outbound endpoints per ruleset,
  # and both must belong to the same resolver instance.
  validation {
    condition     = length(var.dns_resolver_outbound_endpoint_resource_ids) >= 1 && length(var.dns_resolver_outbound_endpoint_resource_ids) <= 2
    error_message = "dns_resolver_outbound_endpoint_resource_ids must hold one or two outbound endpoints."
  }

  validation {
    condition = length(distinct([
      for id in var.dns_resolver_outbound_endpoint_resource_ids : split("/outboundendpoints/", lower(id))[0]
    ])) <= 1
    error_message = "All outbound endpoints of one ruleset must belong to the same DNS resolver."
  }

  validation {
    condition     = length(distinct([for id in var.dns_resolver_outbound_endpoint_resource_ids : lower(id)])) == length(var.dns_resolver_outbound_endpoint_resource_ids)
    error_message = "dns_resolver_outbound_endpoint_resource_ids must not list the same outbound endpoint twice."
  }
}

# -----------------------------------------------------------------------------
# Optional — links
# -----------------------------------------------------------------------------

variable "virtual_network_links" {
  type = map(object({
    name                        = optional(string)
    virtual_network_resource_id = string
    metadata                    = optional(map(string))
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
    Map of virtual networks to link to the ruleset, keyed by a stable identifier. The map key is
    the `for_each` address and the output key, and the link's ARM name when `name` is unset.
    Resources in a linked network resolve through the ruleset's forwarding rules.

    Fields:
    - `name` (optional) — ARM link name; defaults to the map key.
    - `virtual_network_resource_id` (required) — the network to link. It must be in the
      ruleset's region, and a network can be linked to only one ruleset. ARM rejects a change
      to it on an existing link — add a new key and remove the old one instead.
    - `metadata` (optional) — string key/value pairs attached to the link.
  EOT

  validation {
    condition = alltrue([
      for k, v in var.virtual_network_links :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+$", v.virtual_network_resource_id))
    ])
    error_message = "Each virtual_network_resource_id must be the resource ID of a virtual network, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>."
  }

  validation {
    condition     = length(var.virtual_network_links) <= 500
    error_message = "A DNS forwarding ruleset supports at most 500 virtual network links."
  }

  # ARM names are case-insensitive, so two entries differing only in case would
  # address the same link and overwrite each other on every apply.
  validation {
    condition     = length(distinct([for k, v in var.virtual_network_links : lower(coalesce(v.name, k))])) == length(var.virtual_network_links)
    error_message = "Link names must be unique within the ruleset, compared case-insensitively."
  }

  validation {
    condition     = length(distinct([for k, v in var.virtual_network_links : lower(v.virtual_network_resource_id)])) == length(var.virtual_network_links)
    error_message = "Each virtual network can be linked to the ruleset only once."
  }
}

# -----------------------------------------------------------------------------
# Optional — access
# -----------------------------------------------------------------------------

variable "role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string, null)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Map of ruleset-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Network Contributor`), resolved by a subscription-scope lookup.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is generated — unless you
    are adopting an assignment that already exists, where the existing GUID must be supplied to avoid a
    destroy-and-recreate.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal or a managed
    identity, so ARM skips the directory lookup that fails on a principal created moments earlier.

    Do not edit `principal_id` or `role_definition_id_or_name` on an existing key — ARM rejects the update.
    Add a new key and remove the old one instead.

    Mirrors AVM's standard `role_assignments` interface block.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in var.role_assignments :
      assignment.name == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", assignment.name))
    ])
    error_message = "role_assignments `name`, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the DNS forwarding ruleset. Virtual network links do not take tags."
}
