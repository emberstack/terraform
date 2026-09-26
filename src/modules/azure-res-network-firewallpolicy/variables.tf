# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the firewall policy."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the policy in. Resolved against the provider's subscription. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the policy."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "firewall_policy_sku" {
  type        = string
  default     = "Standard"
  description = "Policy tier: `Basic`, `Standard` or `Premium`. Must match the tier of the firewalls that use it."
  nullable    = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.firewall_policy_sku)
    error_message = "firewall_policy_sku must be one of: Basic, Standard, Premium."
  }
}

variable "firewall_policy_threat_intelligence_mode" {
  type        = string
  default     = "Alert"
  description = "Threat intelligence filtering: `Off`, `Alert` or `Deny`. `Alert` is Azure's default."
  nullable    = false

  validation {
    condition     = contains(["Off", "Alert", "Deny"], var.firewall_policy_threat_intelligence_mode)
    error_message = "firewall_policy_threat_intelligence_mode must be one of: Off, Alert, Deny."
  }
}

variable "firewall_policy_intrusion_detection" {
  type = object({
    mode                = string
    private_ranges      = optional(list(string), [])
    signature_overrides = optional(map(string), {})
    traffic_bypass = optional(list(object({
      name                  = string
      protocol              = string
      description           = optional(string, null)
      source_addresses      = optional(list(string), null)
      source_ip_groups      = optional(list(string), null)
      destination_addresses = optional(list(string), null)
      destination_ip_groups = optional(list(string), null)
      destination_ports     = optional(list(string), null)
    })), [])
  })
  default     = null
  description = <<-EOT
    IDPS settings. Premium tier only. Null leaves IDPS at Azure's default, off.

    - `mode`: `Off`, `Alert` or `Deny`.
    - `private_ranges`: ranges IDPS treats as private; empty means Azure's default.
    - `signature_overrides`: signature ID to `Off`, `Alert` or `Deny`.
    - `traffic_bypass`: flows IDPS does not inspect. `protocol` is `TCP`, `UDP`, `ICMP`
      or `ANY`.

    The lists are always sent, empty included — ARM writes are full replaces, so
    leaving one out would keep a bypass or override that configuration no longer has.
  EOT

  validation {
    condition     = var.firewall_policy_intrusion_detection == null || contains(["Off", "Alert", "Deny"], try(var.firewall_policy_intrusion_detection.mode, ""))
    error_message = "firewall_policy_intrusion_detection.mode must be one of: Off, Alert, Deny."
  }

  validation {
    condition = var.firewall_policy_intrusion_detection == null || alltrue([
      for mode in values(try(var.firewall_policy_intrusion_detection.signature_overrides, {})) : contains(["Off", "Alert", "Deny"], mode)
    ])
    error_message = "firewall_policy_intrusion_detection.signature_overrides values must be one of: Off, Alert, Deny."
  }

  validation {
    condition = var.firewall_policy_intrusion_detection == null || alltrue([
      for bypass in try(var.firewall_policy_intrusion_detection.traffic_bypass, []) : contains(["TCP", "UDP", "ICMP", "ANY"], bypass.protocol)
    ])
    error_message = "firewall_policy_intrusion_detection.traffic_bypass protocol must be one of: TCP, UDP, ICMP, ANY."
  }

  validation {
    condition     = var.firewall_policy_intrusion_detection == null || var.firewall_policy_sku == "Premium"
    error_message = "firewall_policy_intrusion_detection requires firewall_policy_sku = \"Premium\"."
  }
}

variable "firewall_policy_dns" {
  type = object({
    proxy_enabled = optional(bool, false)
    servers       = optional(list(string), [])
  })
  default     = null
  description = <<-EOT
    DNS settings for the firewalls using this policy.

    - `proxy_enabled`: the firewall answers DNS on its private IP — required for FQDNs
      in network rules.
    - `servers`: custom DNS servers the firewall forwards to. Empty uses Azure DNS.

    Null leaves DNS at Azure's default: no proxy, Azure DNS.
  EOT
}

variable "firewall_policy_private_ip_ranges" {
  type        = list(string)
  default     = null
  description = <<-EOT
    Destination ranges the firewall treats as private and does NOT source-NAT
    (`snat.privateRanges`). Null keeps Azure's default, the IANA private ranges.

    Setting it REPLACES that default rather than adding to it: include
    `IANAPrivateRanges`, or the RFC 1918 and RFC 6598 blocks, alongside any public
    ranges reached over a private path. Applies to network rules only — application
    rules always SNAT.
  EOT
}

variable "firewall_policy_base_policy_id" {
  type        = string
  default     = null
  description = "Resource ID of a parent firewall policy whose rules this one inherits. Null for a standalone policy."

  validation {
    condition     = var.firewall_policy_base_policy_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/firewallPolicies/[^/]+$", var.firewall_policy_base_policy_id))
    error_message = "firewall_policy_base_policy_id must be a Microsoft.Network/firewallPolicies resource ID."
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
    Map of policy-scope role assignments, keyed by a stable identifier.

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
    - `name`: optional. Defaults to `lock-<policy-name>`.

    ⚠️ A `ReadOnly` lock also blocks writes to the policy's rule collection groups.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the policy."
}
