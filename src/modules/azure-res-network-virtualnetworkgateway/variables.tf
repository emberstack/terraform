# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the virtual network gateway."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the gateway in. Resolved against the provider's subscription. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the gateway. Must be the region of the virtual network that holds `subnet_resource_id`."
  nullable    = false
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the virtual network's `GatewaySubnet`. Every IP configuration attaches to it — Azure deploys gateways into no other subnet."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/GatewaySubnet$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be the resource ID of a subnet named GatewaySubnet."
  }
}

variable "sku" {
  type        = string
  description = "Gateway SKU, e.g. `VpnGw2AZ` or `ErGw1AZ`. Sent as both the SKU name and the SKU tier."
  nullable    = false

  # The values of `VirtualNetworkGatewaySkuName` in the Microsoft.Network
  # 2025-07-01 REST specification. The embedded AzAPI schema models the enum as
  # an open string, so without this a typo reaches ARM.
  validation {
    condition = contains([
      "Basic", "HighPerformance", "Standard", "UltraPerformance",
      "VpnGw1", "VpnGw2", "VpnGw3", "VpnGw4", "VpnGw5",
      "VpnGw1AZ", "VpnGw2AZ", "VpnGw3AZ", "VpnGw4AZ", "VpnGw5AZ",
      "ErGw1AZ", "ErGw2AZ", "ErGw3AZ", "ErGwScale",
    ], var.sku)
    error_message = "sku must be one of: Basic, HighPerformance, Standard, UltraPerformance, VpnGw1-VpnGw5, VpnGw1AZ-VpnGw5AZ, ErGw1AZ, ErGw2AZ, ErGw3AZ, ErGwScale."
  }
}

variable "ip_configurations" {
  type = map(object({
    public_ip_address_resource_id = string
    apipa_addresses               = optional(list(string), [])
  }))
  description = <<-EOT
    Gateway IP configurations, keyed by configuration name — the key is the ARM name
    of the configuration and of its BGP peering address entry.

    - `public_ip_address_resource_id`: an existing Standard, static public IP address.
      The module does not create public IPs.
    - `apipa_addresses`: custom Azure APIPA BGP addresses for this instance, from
      `169.254.21.0` through `169.254.22.255`. Only needed when an on-premises BGP
      peer uses an APIPA address. Requires `vpn_bgp_settings`.

    One entry for an active-standby gateway, two for active-active — see
    `vpn_active_active_enabled`. A third, point-to-site configuration is not
    supported.

    Mirrors the archived AVM `ip_configurations` input, with `public_ip` reduced to
    the ID of an address owned elsewhere.
  EOT
  nullable    = false

  validation {
    condition     = length(var.ip_configurations) == (var.vpn_active_active_enabled ? 2 : 1)
    error_message = "ip_configurations must hold exactly two entries when vpn_active_active_enabled is true, and exactly one when it is false."
  }

  validation {
    condition = alltrue([
      for key in keys(var.ip_configurations) :
      can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", key))
    ])
    error_message = "ip_configurations keys become ARM names: 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }

  validation {
    condition = alltrue([
      for config in values(var.ip_configurations) :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/publicIPAddresses/[^/]+$", config.public_ip_address_resource_id))
    ])
    error_message = "Each public_ip_address_resource_id must be a public IP address resource ID."
  }

  validation {
    condition = alltrue(flatten([
      for config in values(var.ip_configurations) : [
        for address in config.apipa_addresses :
        can(regex("^169\\.254\\.2[12]\\.(25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])$", address))
      ]
    ]))
    error_message = "apipa_addresses must fall within 169.254.21.0 - 169.254.22.255, the range Azure reserves for custom APIPA BGP addresses."
  }

  # APIPA addresses travel inside `bgpSettings`, which is only sent when BGP
  # settings are supplied. Without this they would be dropped silently.
  validation {
    condition = var.vpn_bgp_settings != null || alltrue([
      for config in values(var.ip_configurations) : length(config.apipa_addresses) == 0
    ])
    error_message = "apipa_addresses require vpn_bgp_settings to be set."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "type" {
  type        = string
  default     = "Vpn"
  description = "Gateway type: `Vpn` or `ExpressRoute`."
  nullable    = false

  validation {
    condition     = contains(["Vpn", "ExpressRoute"], var.type)
    error_message = "type must be one of: Vpn, ExpressRoute."
  }
}

variable "vpn_type" {
  type        = string
  default     = "RouteBased"
  description = "VPN routing type: `RouteBased` or `PolicyBased`."
  nullable    = false

  validation {
    condition     = contains(["RouteBased", "PolicyBased"], var.vpn_type)
    error_message = "vpn_type must be one of: RouteBased, PolicyBased."
  }
}

variable "vpn_generation" {
  type        = string
  default     = "Generation2"
  description = "VPN gateway generation: `Generation1` or `Generation2`. Ignored for an ExpressRoute gateway, which ARM requires to send `None`."
  nullable    = false

  validation {
    condition     = contains(["Generation1", "Generation2"], var.vpn_generation)
    error_message = "vpn_generation must be one of: Generation1, Generation2."
  }
}

variable "vpn_active_active_enabled" {
  type        = bool
  default     = false
  description = "Run both gateway instances active, each on its own IP configuration and public IP. Requires two `ip_configurations`."
  nullable    = false
}

variable "vpn_bgp_enabled" {
  type        = bool
  default     = false
  description = "Enable BGP on the gateway."
  nullable    = false
}

variable "vpn_bgp_settings" {
  type = object({
    asn         = optional(number, 65515)
    peer_weight = optional(number, 0)
  })
  default     = null
  description = <<-EOT
    BGP speaker settings. Null leaves ARM's defaults (ASN 65515, weight 0) and sends no
    BGP settings at all — which also means no `apipa_addresses`.

    - `asn`: the gateway's ASN, public or private, 16- or 32-bit. `65515` is Azure's
      own default for the gateway and is accepted; the other ASNs Azure and IANA
      reserve are rejected.
    - `peer_weight`: weight added to routes learned from this speaker.
  EOT

  validation {
    condition = var.vpn_bgp_settings == null || (
      try(floor(var.vpn_bgp_settings.asn) == var.vpn_bgp_settings.asn, false) &&
      try(var.vpn_bgp_settings.asn >= 1 && var.vpn_bgp_settings.asn <= 4294967294, false)
    )
    error_message = "vpn_bgp_settings.asn must be a whole number from 1 to 4294967294."
  }

  # The reserved ASNs listed in the VPN Gateway FAQ ("What ASNs can I use?"),
  # except 65515: that is the ASN Azure assigns a gateway by default, so a
  # gateway may keep it — the reservation is against on-premises peers using it.
  validation {
    condition = var.vpn_bgp_settings == null || !try(
      contains([8074, 8075, 12076, 23456, 65517, 65518, 65519, 65520], var.vpn_bgp_settings.asn) ||
      (var.vpn_bgp_settings.asn >= 64496 && var.vpn_bgp_settings.asn <= 64511) ||
      (var.vpn_bgp_settings.asn >= 65535 && var.vpn_bgp_settings.asn <= 65551),
      false
    )
    error_message = "vpn_bgp_settings.asn is reserved by Azure (8074, 8075, 12076, 65517-65520) or IANA (23456, 64496-64511, 65535-65551)."
  }

  validation {
    condition     = var.vpn_bgp_settings == null || try(var.vpn_bgp_settings.peer_weight >= 0 && floor(var.vpn_bgp_settings.peer_weight) == var.vpn_bgp_settings.peer_weight, false)
    error_message = "vpn_bgp_settings.peer_weight must be a non-negative whole number."
  }
}

variable "vpn_private_ip_address_enabled" {
  type        = bool
  default     = false
  description = "Allow connections to the gateway's private IP addresses, e.g. site-to-site over ExpressRoute private peering."
  nullable    = false
}

variable "vpn_ip_sec_replay_protection_enabled" {
  type        = bool
  default     = true
  description = "IPsec replay protection. Sent as ARM's inverted `disableIPSecReplayProtection`."
  nullable    = false
}

variable "vpn_bgp_route_translation_for_nat_enabled" {
  type        = bool
  default     = false
  description = "Translate BGP routes through the gateway's NAT rules."
  nullable    = false
}

variable "express_route_remote_vnet_traffic_enabled" {
  type        = bool
  default     = false
  description = "Accept traffic from other Azure virtual networks (`allowRemoteVnetTraffic`)."
  nullable    = false
}

variable "express_route_virtual_wan_traffic_enabled" {
  type        = bool
  default     = false
  description = "Accept traffic from remote Virtual WAN networks (`allowVirtualWanTraffic`)."
  nullable    = false
}

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(map(bool), {})
    log_groups                               = optional(map(bool), { allLogs = true })
    metric_categories                        = optional(map(bool), { AllMetrics = true })
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the gateway, keyed by stable name.

    A gateway's log categories are `GatewayDiagnosticLog`, `TunnelDiagnosticLog`,
    `RouteDiagnosticLog`, `IKEDiagnosticLog` and `P2SDiagnosticLog`; its metrics
    category is `AllMetrics`.

    At least one destination must be set per entry.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for setting in values(var.diagnostic_settings) :
      setting.workspace_resource_id != null || setting.storage_account_resource_id != null ||
      setting.event_hub_authorization_rule_resource_id != null || setting.marketplace_partner_resource_id != null
    ])
    error_message = "Each diagnostic_settings entry needs a destination: workspace_resource_id, storage_account_resource_id, event_hub_authorization_rule_resource_id or marketplace_partner_resource_id."
  }
}

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
    Map of gateway-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Reader`), resolved by a subscription-scope lookup.

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

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Resource lock configuration.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<gateway-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

variable "timeouts" {
  type = object({
    create = optional(string, "90m")
    read   = optional(string, "5m")
    update = optional(string, "60m")
    delete = optional(string, "120m")
  })
  default     = {}
  description = <<-EOT
    Operation timeouts for the gateway itself. The children are fast and use the
    provider defaults.

    Azure documents a gateway create as often taking 45 minutes or more, and SKU or
    active-active changes are long-running updates too. AzAPI's own 30-minute
    default would abandon those mid-flight, so the defaults here are the ones the
    azurerm provider uses for this resource.
  EOT
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the gateway."
}
