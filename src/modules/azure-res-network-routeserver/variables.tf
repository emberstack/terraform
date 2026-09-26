# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the route server."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the route server and its public IP in. Resolved against the provider's subscription. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the route server and its public IP. Must be the region of the virtual network that holds `subnet_resource_id`."
  nullable    = false
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the virtual network's `RouteServerSubnet` (/26 or larger). Azure deploys a route server into no other subnet."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/RouteServerSubnet$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be the resource ID of a subnet named RouteServerSubnet."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "enable_branch_to_branch" {
  type        = bool
  default     = false
  description = "Exchange routes between the route server's BGP peers and the virtual network gateways — the transit that lets an NVA reach on-premises through a VPN or ExpressRoute gateway (`allowBranchToBranchTraffic`)."
  nullable    = false
}

variable "hub_routing_preference" {
  type        = string
  default     = "ExpressRoute"
  description = "Route preference when the same prefix is learned from more than one source: `ExpressRoute`, `VpnGateway` or `ASPath`."
  nullable    = false

  validation {
    condition     = contains(["ExpressRoute", "VpnGateway", "ASPath"], var.hub_routing_preference)
    error_message = "hub_routing_preference must be one of: ExpressRoute, VpnGateway, ASPath."
  }
}

variable "routing_infrastructure_units" {
  type        = number
  default     = 2
  description = "Route server capacity in routing infrastructure units (`virtualRouterAutoScaleConfiguration.minCapacity`). Azure's default is 2."
  nullable    = false

  validation {
    condition     = var.routing_infrastructure_units >= 0 && floor(var.routing_infrastructure_units) == var.routing_infrastructure_units
    error_message = "routing_infrastructure_units must be a non-negative whole number."
  }
}

variable "ip_configuration_name" {
  type        = string
  default     = "ipConfig1"
  description = "Name of the route server's IP configuration. `ipConfig1` is what the azurerm provider creates, so an adopted route server keeps its existing child."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.ip_configuration_name))
    error_message = "ip_configuration_name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "routeserver_public_ip_config" {
  type = object({
    name                             = optional(string, null)
    zones                            = optional(list(string), ["1", "2", "3"])
    ddos_protection_mode             = optional(string, "VirtualNetworkInherited")
    ddos_protection_plan_resource_id = optional(string, null)
    tags                             = optional(map(string), null)
  })
  default     = {}
  description = <<-EOT
    The route server's public IP, which this module creates. Azure requires one — a
    Standard, static address the route server uses to reach its management service —
    and it serves nothing else.

    - `name`: defaults to `<name>-pip`.
    - `zones`: availability zones. Defaults to zone-redundant. Pass `[]` for a
      non-zonal address. ⚠️ Zones cannot change after creation — a different value
      replaces the public IP, which the route server is using.
    - `ddos_protection_mode`: `VirtualNetworkInherited`, `Enabled` or `Disabled`.
    - `ddos_protection_plan_resource_id`: only with `Enabled`.
    - `tags`: defaults to `tags`.

    Mirrors a subset of AVM's `routeserver_public_ip_config`. SKU, tier and allocation
    are fixed: a route server needs a Standard address (Standard v2 is not supported),
    the Global tier exists only for cross-region load balancers, and a Standard address
    is always static.
  EOT
  nullable    = false

  validation {
    condition     = var.routeserver_public_ip_config.name == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.routeserver_public_ip_config.name))
    error_message = "routeserver_public_ip_config.name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }

  validation {
    condition     = alltrue([for zone in var.routeserver_public_ip_config.zones : contains(["1", "2", "3"], zone)])
    error_message = "routeserver_public_ip_config.zones may only contain \"1\", \"2\" and \"3\"."
  }

  validation {
    condition     = contains(["VirtualNetworkInherited", "Enabled", "Disabled"], var.routeserver_public_ip_config.ddos_protection_mode)
    error_message = "routeserver_public_ip_config.ddos_protection_mode must be one of: VirtualNetworkInherited, Enabled, Disabled."
  }

  validation {
    condition     = var.routeserver_public_ip_config.ddos_protection_plan_resource_id == null || var.routeserver_public_ip_config.ddos_protection_mode == "Enabled"
    error_message = "routeserver_public_ip_config.ddos_protection_plan_resource_id can only be set when ddos_protection_mode is Enabled."
  }
}

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
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
    Diagnostic settings on the route server, keyed by stable name.

    A route server has no log categories, only the `AllMetrics` metrics category, so
    this input carries no log fields.

    At least one destination must be set per entry.
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
    Map of route-server-scope role assignments, keyed by a stable identifier.

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
    - `name`: optional. Defaults to `lock-<route-server-name>`.

    ⚠️ A `ReadOnly` lock also blocks writes to the route server's children, including
    BGP connections made with `modules/bgp-connection`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

variable "timeouts" {
  type = object({
    create = optional(string, "60m")
    read   = optional(string, "5m")
    update = optional(string, "60m")
    delete = optional(string, "60m")
  })
  default     = {}
  description = <<-EOT
    Operation timeouts for the route server and its IP configuration. The other
    children are fast and use the provider defaults.

    Azure documents a route server deployment as taking up to 30 minutes — AzAPI's own
    default, with no headroom — so the defaults here are the ones the azurerm provider
    uses for this resource.
  EOT
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the route server, and to its public IP unless `routeserver_public_ip_config.tags` is set."
}
