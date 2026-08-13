# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the Azure SignalR Service."
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z][A-Za-z0-9-]{1,61}[A-Za-z0-9]$", var.name))
    error_message = "name must be 3–63 chars, start with a letter, end with letter/digit, and contain only letters, digits, and hyphens."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the SignalR Service should be deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the service will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "sku_name" {
  type        = string
  description = <<-EOT
    SKU name. Examples: `Free_F1`, `Standard_S1`, `Premium_P1`, `Premium_P2`.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — service
# -----------------------------------------------------------------------------

variable "sku_capacity" {
  type        = number
  default     = 1
  description = <<-EOT
    SKU capacity (unit count). The accepted set depends on `sku_name`:

    - `Free_F1`     — 1
    - `Standard_S1` — 1 to 10, then 20, 30 … 100
    - `Premium_P1`  — 1 to 10, then 20, 30 … 100
    - `Premium_P2`  — 100, 200 … 1000

    Note the module default of 1 is not valid for `Premium_P2`; that SKU starts at
    100, so set this explicitly when using it.

    Only those four SKU names are checked. Any other `sku_name` leaves the capacity
    to ARM, so a SKU introduced later is not blocked here.
  EOT
  nullable    = false

  # Each SKU allows a specific set of unit counts rather than a range: no SKU offers
  # 11–19, and only Premium_P2 goes above 100. Sets taken from ResourceSku.capacity
  # in the signalr 2024-03-01 swagger, checked 2026-08-13.
  validation {
    condition = (
      var.sku_name == "Free_F1" ? var.sku_capacity == 1 :
      contains(["Standard_S1", "Premium_P1"], var.sku_name) ? contains([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 20, 30, 40, 50, 60, 70, 80, 90, 100], var.sku_capacity) :
      var.sku_name == "Premium_P2" ? contains([100, 200, 300, 400, 500, 600, 700, 800, 900, 1000], var.sku_capacity) :
      true
    )
    error_message = "sku_capacity is not a unit count this sku_name accepts. Free_F1 allows 1; Standard_S1 and Premium_P1 allow 1–10 then 20, 30 … 100; Premium_P2 allows 100, 200 … 1000."
  }
}

variable "service_mode" {
  type        = string
  default     = "Default"
  description = <<-EOT
    Service mode. One of: `Default`, `Serverless`, `Classic`.

    - `Default`: bidirectional streaming with persistent backend connections.
    - `Serverless`: client connections only — backend uses Upstream Endpoints
      (Azure Functions / Webhooks) to receive events.
    - `Classic`: legacy mode — avoid for new deployments.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Default", "Serverless", "Classic"], var.service_mode)
    error_message = "service_mode must be one of: Default, Serverless, Classic."
  }
}

variable "serverless_connection_timeout_in_seconds" {
  type        = number
  default     = 30
  description = "Serverless mode connection timeout (seconds). Range: 1–120. Only meaningful when `service_mode = \"Serverless\"`."
  nullable    = false

  validation {
    condition     = var.serverless_connection_timeout_in_seconds >= 1 && var.serverless_connection_timeout_in_seconds <= 120
    error_message = "serverless_connection_timeout_in_seconds must be between 1 and 120."
  }
}

variable "cors_allowed_origins" {
  type        = list(string)
  default     = null
  description = "List of CORS allowed origins. `null` (default) leaves the resource defaults; pass `[\"*\"]` to allow all."
}

variable "upstream_endpoints" {
  type = list(object({
    url_template              = string
    category_pattern          = optional(list(string), ["*"])
    event_pattern             = optional(list(string), ["*"])
    hub_pattern               = optional(list(string), ["*"])
    managed_identity_audience = optional(string, null)
  }))
  default     = []
  description = <<-EOT
    Upstream endpoints for `Serverless` service mode. Each entry routes events
    matching the given category/event/hub patterns to the URL template.

    - `managed_identity_audience`: when set, the service authenticates to the
      upstream with a managed identity and this value becomes the token's
      audience (`aud` claim) — the target's Application ID URI or resource URI,
      shown in the portal as "Audience in the issued token". It is *not* a
      managed identity resource ID. Which identity is used follows the
      service's own `managed_identities` configuration.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — authentication
# -----------------------------------------------------------------------------

variable "local_auth_enabled" {
  type        = bool
  default     = false
  description = "Whether AccessKey-based authentication is enabled. Default: false (Entra ID only). Set to true only when a caller cannot yet use Entra-ID-based passwordless auth."
  nullable    = false
}

variable "aad_auth_enabled" {
  type        = bool
  default     = true
  description = "Whether Entra ID (AAD) authentication is enabled. Default: true."
  nullable    = false
}

variable "tls_client_cert_enabled" {
  type        = bool
  default     = false
  description = "Whether TLS client certificate authentication is enabled. Default: false."
  nullable    = false
}

variable "include_access_keys" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether to read the service's access keys and expose them as outputs.

    Off by default: reading them costs an extra `listKeys` call on every plan and needs a wider
    role than deploying does. With `local_auth_enabled = false` the keys are inert, so most
    callers never want them.
  EOT
  nullable    = false
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
    Managed identity configuration for the SignalR Service.

    - `system_assigned`: enable a system-assigned identity.
    - `user_assigned_resource_ids`: set of UAI resource IDs to attach.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — networking
# -----------------------------------------------------------------------------

variable "public_network_access_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether the service is reachable from the public internet. Default: true.
    Combine with `network_acl` to actually restrict request types when true.
  EOT
  nullable    = false
}

variable "network_acl" {
  type = object({
    default_action = optional(string, "Deny")
    public_network = optional(object({
      allowed_request_types = optional(list(string), null)
      denied_request_types  = optional(list(string), null)
    }))
    private_endpoints = optional(map(object({
      allowed_request_types = optional(list(string), null)
      denied_request_types  = optional(list(string), null)
    })), {})
  })
  default     = null
  description = <<-EOT
    Network ACL configuration. Written by `azapi_update_resource.network_acl` in
    this module, after the private endpoints exist — exactly one ACL per SignalR
    service.

    - `default_action`: `Allow` or `Deny` (default: `Deny`).
    - `public_network`: optional public-network-side rules.
    - `private_endpoints`: per-PE rules, keyed by the same map keys used in
      `var.private_endpoints` (the PE referenced must exist in this module).

    Request types: `ClientConnection`, `ServerConnection`, `RESTAPI`, `Trace`.
  EOT

  validation {
    condition     = var.network_acl == null || contains(["Allow", "Deny"], try(var.network_acl.default_action, "Deny"))
    error_message = "network_acl.default_action must be 'Allow' or 'Deny'."
  }
}

variable "private_endpoints" {
  type = map(object({
    name = optional(string, null)
    role_assignments = optional(map(object({
      name                                   = optional(string, null)
      role_definition_id_or_name             = string
      principal_id                           = string
      description                            = optional(string, null)
      condition                              = optional(string, null)
      condition_version                      = optional(string, null)
      delegated_managed_identity_resource_id = optional(string, null)
      principal_type                         = optional(string, null)
    })), {})
    lock = optional(object({
      kind = string
      name = optional(string, null)
    }), null)
    tags                                    = optional(map(string), null)
    subnet_resource_id                      = string
    subresource_name                        = optional(string, "signalr")
    private_dns_zone_group_name             = optional(string, "default")
    private_dns_zone_resource_ids           = optional(set(string), [])
    application_security_group_associations = optional(map(string), {})
    private_service_connection_name         = optional(string, null)
    network_interface_name                  = optional(string, null)
    location                                = optional(string, null)
    resource_group_name                     = optional(string, null)
    ip_configurations = optional(map(object({
      name               = string
      private_ip_address = string
      subresource_name   = optional(string, null)
      member_name        = optional(string, null)
    })), {})
  }))
  default     = {}
  description = <<-EOT
    Private endpoints keyed by stable name. Shape mirrors AVM standard.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal
    or a managed identity, so ARM skips the directory lookup that fails on a principal
    created moments earlier.

    Map keys — both the endpoint keys and the nested `role_assignments` keys — must
    be snake_case handles (`^[a-z0-9]+(_[a-z0-9]+)*$`), see the validations below.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for k in keys(var.private_endpoints) : can(regex("^[a-z0-9]+(_[a-z0-9]+)*$", k))])
    error_message = <<-EOT
      Every private_endpoints key must match ^[a-z0-9]+(_[a-z0-9]+)*$ (lower-case
      snake_case). A per-endpoint role assignment is addressed in state by joining
      the endpoint key and the assignment key with "-", so a key containing "-"
      would let two different pairs collide on one address: ("a-b", "c") and
      ("a", "b-c") both produce "a-b-c".
    EOT
  }

  validation {
    condition = alltrue(flatten([
      for pe_k, pe_v in var.private_endpoints : [
        for ra_k in keys(pe_v.role_assignments) : can(regex("^[a-z0-9]+(_[a-z0-9]+)*$", ra_k))
      ]
    ]))
    error_message = <<-EOT
      Every key of a private_endpoints[*].role_assignments map must match
      ^[a-z0-9]+(_[a-z0-9]+)*$ (lower-case snake_case), for the same reason as the
      endpoint keys: the two are joined with "-" to form the state address.
    EOT
  }
}

variable "private_endpoints_manage_dns_zone_group" {
  type        = bool
  default     = true
  description = "Whether the module manages private DNS zone groups. Set to false to manage zone groups externally (e.g. via Azure Policy)."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — diagnostics
# -----------------------------------------------------------------------------

variable "connectivity_logs_enabled" {
  type        = bool
  default     = false
  description = "Whether connectivity logs are emitted. Default: false."
  nullable    = false
}

variable "messaging_logs_enabled" {
  type        = bool
  default     = false
  description = "Whether messaging logs are emitted. Default: false."
  nullable    = false
}

variable "http_request_logs_enabled" {
  type        = bool
  default     = false
  description = "Whether HTTP request logs are emitted. Default: false."
  nullable    = false
}

variable "live_trace" {
  type = object({
    enabled                   = optional(bool, true)
    messaging_logs_enabled    = optional(bool, true)
    connectivity_logs_enabled = optional(bool, true)
    http_request_logs_enabled = optional(bool, true)
  })
  default     = null
  description = <<-EOT
    Live trace configuration block. Supersedes the legacy
    `live_trace_enabled` boolean. Set to a non-null object to enable live
    tracing with per-category control.
  EOT
}

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(set(string), [])
    log_groups                               = optional(set(string), ["allLogs"])
    metric_categories                        = optional(set(string), ["AllMetrics"])
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the SignalR Service, keyed by stable name.

    Exactly one destination must be set per entry.
  EOT
  nullable    = false
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
    Role assignments scoped to the SignalR Service, keyed by stable name.

    `role_definition_id_or_name` accepts either a role name (e.g. `"Reader"`) or
    a full role definition resource ID. Auto-routed by the leading `/`.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal
    or a managed identity, so ARM skips the directory lookup that fails on a principal
    created moments earlier.
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
# Optional — protection
# -----------------------------------------------------------------------------

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Resource lock configuration.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<signalr-name>`.
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
  description = "Tags applied to the SignalR Service."
}
