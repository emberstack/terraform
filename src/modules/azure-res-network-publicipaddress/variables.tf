# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Public IP address name."
  nullable    = false

  # Azure's rule for publicIPAddresses: 1-80 characters of alphanumerics,
  # underscores, periods and hyphens, starting alphanumeric and ending
  # alphanumeric or underscore (resource-name-rules table, Microsoft.Network).
  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the address will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the address. A Global-tier address still has a home region."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — SKU and placement
# -----------------------------------------------------------------------------

variable "sku" {
  type        = string
  default     = "Standard"
  description = "`Standard` or `StandardV2`. The SKU cannot change after creation, and must match the SKU of `public_ip_prefix_resource_id` when one is set. Mirrors AVM's `sku`."
  nullable    = false

  validation {
    condition     = contains(["Standard", "StandardV2"], var.sku)
    error_message = "sku must be Standard or StandardV2."
  }
}

variable "sku_tier" {
  type        = string
  default     = "Regional"
  description = "`Regional`, or `Global` for an address fronting a cross-region load balancer. Mirrors AVM's `sku_tier`."
  nullable    = false

  validation {
    condition     = contains(["Regional", "Global"], var.sku_tier)
    error_message = "sku_tier must be Regional or Global."
  }
}

variable "zones" {
  type        = list(string)
  default     = ["1", "2", "3"]
  description = "Availability zones. Defaults to zone-redundant; pass `[]` for a non-zonal address. ⚠️ Zones cannot change after creation — a different value replaces the address, and the IP with it. Mirrors AVM's `zones`."
  nullable    = false

  validation {
    condition     = alltrue([for zone in var.zones : contains(["1", "2", "3"], zone)])
    error_message = "zones may only contain \"1\", \"2\" and \"3\"."
  }

  validation {
    condition     = length(var.zones) == 0 || var.sku_tier == "Regional"
    error_message = "A Global-tier address is not zonal; pass zones = []."
  }
}

variable "public_ip_prefix_resource_id" {
  type        = string
  default     = null
  description = "Resource ID of a public IP prefix to allocate the address from. ⚠️ Cannot change after creation. Mirrors AVM's `public_ip_prefix_id`."

  validation {
    condition     = var.public_ip_prefix_resource_id == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/publicIPPrefixes/[^/]+$", var.public_ip_prefix_resource_id))
    error_message = "public_ip_prefix_resource_id must be the resource ID of a public IP prefix."
  }
}

variable "ip_version" {
  type        = string
  default     = "IPv4"
  description = "`IPv4` or `IPv6`. Mirrors AVM's `ip_version`."
  nullable    = false

  validation {
    condition     = contains(["IPv4", "IPv6"], var.ip_version)
    error_message = "ip_version must be IPv4 or IPv6."
  }
}

variable "idle_timeout_in_minutes" {
  type        = number
  default     = 4
  description = "TCP idle timeout, 4 to 30 minutes. Mirrors AVM's `idle_timeout_in_minutes`."
  nullable    = false

  validation {
    condition     = var.idle_timeout_in_minutes >= 4 && var.idle_timeout_in_minutes <= 30 && floor(var.idle_timeout_in_minutes) == var.idle_timeout_in_minutes
    error_message = "idle_timeout_in_minutes must be an integer from 4 to 30."
  }
}

variable "ip_tags" {
  type        = map(string)
  default     = {}
  description = "IP tags as `{ <ipTagType> = <tag> }`, e.g. `{ RoutingPreference = \"Internet\" }`. Mirrors AVM's `ip_tags`."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — DNS
# -----------------------------------------------------------------------------

variable "domain_name_label" {
  type        = string
  default     = null
  description = "DNS label, giving the address `<label>.<region>.cloudapp.azure.com`. Mirrors AVM's `domain_name_label`."

  # The pattern ARM enforces for a domain name label.
  validation {
    condition     = var.domain_name_label == null || can(regex("^[a-z][a-z0-9-]{1,61}[a-z0-9]$", var.domain_name_label))
    error_message = "domain_name_label must be 3-63 characters of lowercase letters, digits and hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "domain_name_label_scope" {
  type        = string
  default     = null
  description = "Hashed reuse policy for `domain_name_label`: `TenantReuse`, `SubscriptionReuse`, `ResourceGroupReuse` or `NoReuse`. ⚠️ Cannot change after creation."

  validation {
    condition     = var.domain_name_label_scope == null || contains(["TenantReuse", "SubscriptionReuse", "ResourceGroupReuse", "NoReuse"], coalesce(var.domain_name_label_scope, "-"))
    error_message = "domain_name_label_scope must be one of: TenantReuse, SubscriptionReuse, ResourceGroupReuse, NoReuse."
  }

  validation {
    condition     = var.domain_name_label_scope == null || var.domain_name_label != null
    error_message = "domain_name_label_scope needs domain_name_label."
  }
}

variable "reverse_fqdn" {
  type        = string
  default     = null
  description = "Reverse DNS name the address resolves to. Mirrors AVM's `reverse_fqdn`."
}

# -----------------------------------------------------------------------------
# Optional — DDoS
# -----------------------------------------------------------------------------

variable "ddos_protection_mode" {
  type        = string
  default     = "VirtualNetworkInherited"
  description = "`VirtualNetworkInherited`, `Enabled` or `Disabled`. Mirrors AVM's `ddos_protection_mode`."
  nullable    = false

  validation {
    condition     = contains(["VirtualNetworkInherited", "Enabled", "Disabled"], var.ddos_protection_mode)
    error_message = "ddos_protection_mode must be one of: VirtualNetworkInherited, Enabled, Disabled."
  }
}

variable "ddos_protection_plan_resource_id" {
  type        = string
  default     = null
  description = "DDoS protection plan for the address; only with `ddos_protection_mode = \"Enabled\"`. Mirrors AVM's `ddos_protection_plan_id`."

  validation {
    condition     = var.ddos_protection_plan_resource_id == null || var.ddos_protection_mode == "Enabled"
    error_message = "ddos_protection_plan_resource_id can only be set when ddos_protection_mode is Enabled."
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
    Map of public-IP-scope role assignments, keyed by a stable identifier.

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
  description = "Tags to apply to the public IP address."
}
