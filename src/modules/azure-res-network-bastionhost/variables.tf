# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Bastion host name."
  nullable    = false

  # Azure's rule for bastionHosts: 1-80 characters of alphanumerics, underscores,
  # periods and hyphens, starting alphanumeric and ending alphanumeric or
  # underscore (resource-name-rules table, Microsoft.Network).
  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9._-]{0,78}[A-Za-z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the bastion host and its public IP will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region for the bastion host and its public IP. Must be the region of the virtual network that holds `subnet_resource_id`."
  nullable    = false
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the virtual network's `AzureBastionSubnet` (/26 or larger). Azure deploys a dedicated bastion into no other subnet."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/AzureBastionSubnet$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be the resource ID of a subnet named AzureBastionSubnet."
  }
}

# -----------------------------------------------------------------------------
# Optional — SKU and scale
# -----------------------------------------------------------------------------

variable "sku" {
  type        = string
  default     = "Basic"
  description = "Bastion SKU: `Basic`, `Standard` or `Premium`. Mirrors AVM's `sku` and its default. Developer is not supported by this module."
  nullable    = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of: Basic, Standard, Premium."
  }
}

variable "scale_units" {
  type        = number
  default     = 2
  description = "Number of bastion instances, 2 to 50. Basic is fixed at 2; host scaling needs Standard or Premium."
  nullable    = false

  validation {
    condition     = var.scale_units >= 2 && var.scale_units <= 50 && floor(var.scale_units) == var.scale_units
    error_message = "scale_units must be an integer from 2 to 50."
  }

  validation {
    condition     = var.scale_units == 2 || var.sku != "Basic"
    error_message = "scale_units other than 2 needs the Standard or Premium SKU."
  }
}

variable "zones" {
  type        = list(string)
  default     = []
  description = "Availability zones for the bastion host. Defaults to none. ⚠️ Zones cannot change after creation."
  nullable    = false

  validation {
    condition     = alltrue([for zone in var.zones : contains(["1", "2", "3"], zone)])
    error_message = "zones may only contain \"1\", \"2\" and \"3\"."
  }
}

# -----------------------------------------------------------------------------
# Optional — features
# -----------------------------------------------------------------------------
# SKU requirements come from the Bastion SKU comparison: everything below except
# Kerberos needs Standard or higher, and session recording needs Premium.

variable "copy_paste_enabled" {
  type        = bool
  default     = true
  description = "Allow copy and paste in web-based sessions. Disabling it needs the Standard or Premium SKU."
  nullable    = false

  validation {
    condition     = var.copy_paste_enabled || var.sku != "Basic"
    error_message = "Disabling copy and paste needs the Standard or Premium SKU."
  }
}

variable "file_copy_enabled" {
  type        = bool
  default     = false
  description = "Allow file upload and download through the native client. Needs the Standard or Premium SKU."
  nullable    = false

  validation {
    condition     = !var.file_copy_enabled || var.sku != "Basic"
    error_message = "file_copy_enabled needs the Standard or Premium SKU."
  }
}

variable "ip_connect_enabled" {
  type        = bool
  default     = false
  description = "Allow connecting to a VM by private IP address. Needs the Standard or Premium SKU."
  nullable    = false

  validation {
    condition     = !var.ip_connect_enabled || var.sku != "Basic"
    error_message = "ip_connect_enabled needs the Standard or Premium SKU."
  }
}

variable "kerberos_enabled" {
  type        = bool
  default     = false
  description = "Allow Kerberos authentication. Available on every SKU this module supports."
  nullable    = false
}

variable "session_recording_enabled" {
  type        = bool
  default     = false
  description = "Record sessions. Needs the Premium SKU, and disables native client support."
  nullable    = false

  validation {
    condition     = !var.session_recording_enabled || var.sku == "Premium"
    error_message = "session_recording_enabled needs the Premium SKU."
  }
}

variable "shareable_link_enabled" {
  type        = bool
  default     = false
  description = "Allow shareable links, which let users without portal access connect to a VM. Needs the Standard or Premium SKU."
  nullable    = false

  validation {
    condition     = !var.shareable_link_enabled || var.sku != "Basic"
    error_message = "shareable_link_enabled needs the Standard or Premium SKU."
  }
}

variable "tunneling_enabled" {
  type        = bool
  default     = false
  description = "Allow native client connections (`az network bastion ssh` / `rdp` / `tunnel`). Needs the Standard or Premium SKU."
  nullable    = false

  validation {
    condition     = !var.tunneling_enabled || var.sku != "Basic"
    error_message = "tunneling_enabled needs the Standard or Premium SKU."
  }
}

# -----------------------------------------------------------------------------
# Optional — network
# -----------------------------------------------------------------------------

variable "ip_configuration_name" {
  type        = string
  default     = "ipconfig"
  description = "Name of the bastion host's IP configuration."
  nullable    = false

  validation {
    condition     = length(var.ip_configuration_name) > 0
    error_message = "ip_configuration_name must not be empty."
  }
}

variable "public_ip_config" {
  type = object({
    name                             = optional(string, null)
    zones                            = optional(list(string), ["1", "2", "3"])
    idle_timeout_in_minutes          = optional(number, 4)
    ddos_protection_mode             = optional(string, "VirtualNetworkInherited")
    ddos_protection_plan_resource_id = optional(string, null)
    tags                             = optional(map(string), null)
  })
  default     = {}
  description = <<-EOT
    The bastion's public IP, which this module creates.

    - `name`: defaults to `<name>-pip`.
    - `zones`: availability zones. Defaults to zone-redundant. Pass `[]` for a
      non-zonal address. ⚠️ Zones cannot change after creation — a different value
      replaces the public IP, which the bastion host is using.
    - `idle_timeout_in_minutes`: TCP idle timeout, 4 to 30.
    - `ddos_protection_mode`: `VirtualNetworkInherited`, `Enabled` or `Disabled`.
    - `ddos_protection_plan_resource_id`: only with `Enabled`.
    - `tags`: defaults to `tags`.

    SKU, tier, allocation and IP version are fixed: a bastion needs a Standard,
    static IPv4 address.
  EOT
  nullable    = false

  validation {
    condition     = var.public_ip_config.name == null || can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.public_ip_config.name))
    error_message = "public_ip_config.name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }

  validation {
    condition     = alltrue([for zone in var.public_ip_config.zones : contains(["1", "2", "3"], zone)])
    error_message = "public_ip_config.zones may only contain \"1\", \"2\" and \"3\"."
  }

  validation {
    condition     = var.public_ip_config.idle_timeout_in_minutes >= 4 && var.public_ip_config.idle_timeout_in_minutes <= 30 && floor(var.public_ip_config.idle_timeout_in_minutes) == var.public_ip_config.idle_timeout_in_minutes
    error_message = "public_ip_config.idle_timeout_in_minutes must be an integer from 4 to 30."
  }

  validation {
    condition     = contains(["VirtualNetworkInherited", "Enabled", "Disabled"], var.public_ip_config.ddos_protection_mode)
    error_message = "public_ip_config.ddos_protection_mode must be one of: VirtualNetworkInherited, Enabled, Disabled."
  }

  validation {
    condition     = var.public_ip_config.ddos_protection_plan_resource_id == null || var.public_ip_config.ddos_protection_mode == "Enabled"
    error_message = "public_ip_config.ddos_protection_plan_resource_id can only be set when ddos_protection_mode is Enabled."
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
    Map of bastion-scope role assignments, keyed by a stable identifier.

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

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the bastion host, and to its public IP unless `public_ip_config.tags` is set."
}
