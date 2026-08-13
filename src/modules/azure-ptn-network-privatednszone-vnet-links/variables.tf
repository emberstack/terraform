# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "private_dns_zone_vnet_links" {
  type = map(object({
    private_dns_zone_resource_id = string
    name                         = string
    virtual_network_resource_id  = string
    registration_enabled         = optional(bool, false)
    # Defaults to null, which leaves `resolutionPolicy` to Azure — it sets the
    # value itself on privatelink zones. Set it explicitly only to pin one of
    # the two accepted values; see the validation below.
    resolution_policy = optional(string, null)
    tags              = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOT
    Map of virtual-network → private-DNS-zone links, keyed by a stable identifier.

    Each entry can target a different zone — useful for matrix scenarios (e.g., linking
    many service zones to many tier hub vnets in one apply). For the simple case of a
    single zone with multiple vnets, use one entry per vnet, all sharing the same
    `private_dns_zone_resource_id`.

    Fields:
    - `private_dns_zone_resource_id` (required) — ARM resource ID of the private DNS zone. The zone name and RG are parsed from this.
    - `name` (required) — the link's name in Azure; typically the vnet's short name.
    - `virtual_network_resource_id` (required) — ARM resource ID of the virtual network to link.
    - `registration_enabled` (optional, default `false`) — when `true`, VMs in the linked vnet auto-register their hostnames in the zone. Only valid for non-privatelink zones.
    - `resolution_policy` (optional, no module default) — `"Default"` or `"NxDomainRedirect"` (the latter is a privatelink-zone-only feature). Omitting it sends `null`, leaving Azure to apply its own default rather than the module forcing one.
    - `tags` (optional) — tags applied to the link; merged with `var.tags`.
  EOT

  validation {
    condition     = alltrue([for k, v in var.private_dns_zone_vnet_links : can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/privatednszones/[^/]+$", v.private_dns_zone_resource_id))])
    error_message = "Each entry's `private_dns_zone_resource_id` must be an ARM resource ID of an Azure private DNS zone."
  }

  validation {
    condition     = alltrue([for k, v in var.private_dns_zone_vnet_links : v.resolution_policy == null || contains(["Default", "NxDomainRedirect"], v.resolution_policy)])
    error_message = "Each entry's `resolution_policy` must be null, `Default`, or `NxDomainRedirect`."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to merge into every link. Per-link `tags` win over these on key collisions."
}
