# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Front Door profile name."
  nullable    = false

  # Azure's rule for Microsoft.Cdn/profiles: 1-260 alphanumerics and hyphens,
  # starting and ending alphanumeric (resource-name-rules table, Microsoft.Cdn).
  validation {
    condition     = length(var.name) <= 260 && can(regex("^[a-zA-Z0-9]+(-*[a-zA-Z0-9])*$", var.name))
    error_message = "name must be 1-260 characters of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the profile will be created. Mirrors AVM `resource_group_name`. The profile itself is global whatever the group's region."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional — tier and behaviour
# -----------------------------------------------------------------------------

variable "sku" {
  type        = string
  default     = "Standard_AzureFrontDoor"
  description = <<-EOT
    Front Door tier: `Standard_AzureFrontDoor` or `Premium_AzureFrontDoor`.

    Premium adds Private Link origins and the WAF's managed rule sets and bot
    protection. The classic Azure CDN SKUs share this resource type but not its
    children, so they are rejected.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Standard_AzureFrontDoor", "Premium_AzureFrontDoor"], var.sku)
    error_message = "sku must be one of: Standard_AzureFrontDoor, Premium_AzureFrontDoor."
  }
}

variable "origin_response_timeout_seconds" {
  type        = number
  default     = 60
  description = "Seconds Front Door waits for the first byte from an origin before failing the request, 16 to 240. Azure's default is 60."
  nullable    = false

  validation {
    condition     = var.origin_response_timeout_seconds >= 16 && var.origin_response_timeout_seconds <= 240 && floor(var.origin_response_timeout_seconds) == var.origin_response_timeout_seconds
    error_message = "origin_response_timeout_seconds must be an integer from 16 to 240."
  }
}

variable "log_scrubbing" {
  type = object({
    enabled = optional(bool, true)
    rules = list(object({
      match_variable = string
      selector       = optional(string, null)
      enabled        = optional(bool, true)
    }))
  })
  default     = null
  description = <<-EOT
    Fields to scrub from the profile's access logs. Null leaves scrubbing unset.

    - `match_variable`: `QueryStringArgNames`, `RequestIPAddress` or `RequestUri`.
    - `selector`: optional, for a collection variable.

    ARM accepts only `EqualsAny` as the selector operator here, so it is not an
    input.
  EOT

  validation {
    condition = var.log_scrubbing == null || alltrue([
      for rule in try(var.log_scrubbing.rules, []) : contains(["QueryStringArgNames", "RequestIPAddress", "RequestUri"], rule.match_variable)
    ])
    error_message = "log_scrubbing rules match_variable must be one of: QueryStringArgNames, RequestIPAddress, RequestUri."
  }
}

# -----------------------------------------------------------------------------
# Optional — identity
# -----------------------------------------------------------------------------

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    Managed identity configuration for the profile.

    - `system_assigned`: enable a system-assigned identity.
    - `user_assigned_resource_ids`: set of UAI resource IDs to attach.

    An origin group's managed-identity origin authentication names one of these
    identities, so it has to be attached here first.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — access and monitoring
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
    Map of profile-scope role assignments, keyed by a stable identifier.

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

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(map(bool), {})
    log_groups                               = optional(map(bool), { allLogs = true })
    metric_categories                        = optional(map(bool), { AllMetrics = true })
    log_analytics_destination_type           = optional(string, null)
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the profile, keyed by stable name.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan. A Front Door profile has three log
    categories, `FrontDoorAccessLog`, `FrontDoorHealthProbeLog` and
    `FrontDoorWebApplicationFirewallLog`, and one metric category, `AllMetrics`.

    `log_analytics_destination_type` is `AzureDiagnostics` or `Dedicated`; leave
    it null unless the destination table matters, since ARM stores whatever it
    decides for the resource.

    Exactly one destination must be set per entry.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for setting in var.diagnostic_settings : length(compact([
        setting.workspace_resource_id,
        setting.storage_account_resource_id,
        setting.event_hub_authorization_rule_resource_id,
        setting.marketplace_partner_resource_id,
      ])) == 1
    ])
    error_message = "Each diagnostic_settings entry must name exactly one destination."
  }

  validation {
    condition = alltrue([
      for setting in var.diagnostic_settings :
      setting.log_analytics_destination_type == null || contains(["AzureDiagnostics", "Dedicated"], coalesce(setting.log_analytics_destination_type, "-"))
    ])
    error_message = "diagnostic_settings log_analytics_destination_type must be AzureDiagnostics or Dedicated when set."
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

    - `kind`: `CanNotDelete` or `ReadOnly`. A `ReadOnly` lock also blocks every
      write to the profile's origin groups, endpoints, routes and security
      policies.
    - `name`: optional. Defaults to `lock-<profile-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

# -----------------------------------------------------------------------------
# Optional — metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the profile."
}
