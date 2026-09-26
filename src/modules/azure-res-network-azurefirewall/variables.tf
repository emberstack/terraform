# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the firewall."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the firewall (and its management public IP) in. Resolved against the provider's subscription. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the firewall. Must be the region of the virtual network that holds `subnet_resource_id`."
  nullable    = false
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the virtual network's `AzureFirewallSubnet` (/26 or larger). It is attached to the primary IP configuration."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/AzureFirewallSubnet$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be the resource ID of a subnet named AzureFirewallSubnet."
  }
}

variable "firewall_sku_tier" {
  type        = string
  description = "Firewall tier: `Basic`, `Standard` or `Premium`. Must match the tier of `firewall_policy_id`."
  nullable    = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_sku_tier)
    error_message = "firewall_sku_tier must be one of: Basic, Standard, Premium."
  }
}

variable "firewall_policy_id" {
  type        = string
  description = "Resource ID of the firewall policy holding the rules — e.g. `azure-res-network-firewallpolicy`'s `resource_id`. Classic, firewall-embedded rules are not supported."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/firewallPolicies/[^/]+$", var.firewall_policy_id))
    error_message = "firewall_policy_id must be a Microsoft.Network/firewallPolicies resource ID."
  }
}

variable "ip_configurations" {
  type = map(object({
    public_ip_address_resource_id = string
    primary                       = optional(bool, false)
  }))
  description = <<-EOT
    The firewall's data-plane IP configurations, keyed by configuration name. Each
    carries one existing Standard, static public IP — the addresses the firewall
    SNATs outbound traffic to and DNATs inbound traffic from. The module does not
    create them.

    Exactly one entry is `primary`: it takes `subnet_resource_id`, holds the
    firewall's private IP, and is sent first. The rest only add public IPs.
  EOT
  nullable    = false

  validation {
    condition     = length([for config in values(var.ip_configurations) : config if config.primary]) == 1
    error_message = "Exactly one ip_configurations entry must set primary = true."
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
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "firewall_management_ip_configuration" {
  type = object({
    name               = optional(string, "management")
    subnet_resource_id = string
    public_ip = optional(object({
      name                             = optional(string, null)
      zones                            = optional(list(string), ["1", "2", "3"])
      ddos_protection_mode             = optional(string, "VirtualNetworkInherited")
      ddos_protection_plan_resource_id = optional(string, null)
      tags                             = optional(map(string), null)
    }), {})
  })
  default     = null
  description = <<-EOT
    A separate management IP configuration, which keeps the firewall's own
    management traffic off the data path — what forced tunnelling needs. Null for
    none.

    - `subnet_resource_id`: the `AzureFirewallManagementSubnet` (/26 or larger).
    - `public_ip`: the management public IP, which this module creates because it
      serves nothing else. `name` defaults to `<name>-mgmt-pip`; `zones` defaults to
      zone-redundant, and ⚠️ cannot change after creation; `tags` default to `tags`.
      SKU, tier and allocation are fixed at Standard, Regional and static.
  EOT

  validation {
    condition     = var.firewall_management_ip_configuration == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/AzureFirewallManagementSubnet$", try(var.firewall_management_ip_configuration.subnet_resource_id, "")))
    error_message = "firewall_management_ip_configuration.subnet_resource_id must be the resource ID of a subnet named AzureFirewallManagementSubnet."
  }

  validation {
    condition     = var.firewall_management_ip_configuration == null || alltrue([for zone in try(var.firewall_management_ip_configuration.public_ip.zones, []) : contains(["1", "2", "3"], zone)])
    error_message = "firewall_management_ip_configuration.public_ip.zones may only contain \"1\", \"2\" and \"3\"."
  }

  validation {
    condition     = var.firewall_management_ip_configuration == null || contains(["VirtualNetworkInherited", "Enabled", "Disabled"], try(var.firewall_management_ip_configuration.public_ip.ddos_protection_mode, ""))
    error_message = "firewall_management_ip_configuration.public_ip.ddos_protection_mode must be one of: VirtualNetworkInherited, Enabled, Disabled."
  }

  validation {
    condition     = var.firewall_management_ip_configuration == null || try(var.firewall_management_ip_configuration.public_ip.ddos_protection_plan_resource_id, null) == null || try(var.firewall_management_ip_configuration.public_ip.ddos_protection_mode, "") == "Enabled"
    error_message = "firewall_management_ip_configuration.public_ip.ddos_protection_plan_resource_id can only be set when ddos_protection_mode is Enabled."
  }
}

variable "firewall_zones" {
  type        = list(string)
  default     = ["1", "2", "3"]
  description = "Availability zones for the firewall. Defaults to zone-redundant; `[]` for none. ⚠️ Fixed at creation — see the note on zones in the README."
  nullable    = false

  validation {
    condition     = alltrue([for zone in var.firewall_zones : contains(["1", "2", "3"], zone)])
    error_message = "firewall_zones may only contain \"1\", \"2\" and \"3\"."
  }
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
    Diagnostic settings on the firewall, keyed by stable name.

    The firewall's log categories are the resource-specific `AZFWNetworkRule`,
    `AZFWApplicationRule`, `AZFWNatRule`, `AZFWThreatIntel`, `AZFWIdpsSignature`,
    `AZFWDnsQuery`, `AZFWDnsAdditional`, `AZFWFqdnResolveFailure`, `AZFWFatFlow`,
    `AZFWFlowTrace`, `AZFWApplicationRuleAggregation`, `AZFWNetworkRuleAggregation`
    and `AZFWNatRuleAggregation`, plus the legacy `AzureFirewallApplicationRule`,
    `AzureFirewallNetworkRule` and `AzureFirewallDnsProxy`. The metrics category is
    `AllMetrics`. The resource-specific categories need `Dedicated` destination
    tables, the default here.

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
    Map of firewall-scope role assignments, keyed by a stable identifier.

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
    - `name`: optional. Defaults to `lock-<firewall-name>`.
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
    update = optional(string, "90m")
    delete = optional(string, "90m")
  })
  default     = {}
  description = <<-EOT
    Operation timeouts for the firewall. Its public IP and the other children are
    fast and use the provider defaults.

    A firewall create or update is a long-running operation, and AzAPI's own
    30-minute default can abandon one mid-flight, so the defaults here are the ones
    the azurerm provider uses for this resource.
  EOT
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the firewall, and to its management public IP unless that sets its own."
}
