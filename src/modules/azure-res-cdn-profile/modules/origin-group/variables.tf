# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "cdn_profile_resource_id" {
  type        = string
  description = "Resource ID of the Front Door profile the origin group belongs to — the parent module's `resource_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Cdn/profiles/[^/]+$", var.cdn_profile_resource_id))
    error_message = "cdn_profile_resource_id must be a Microsoft.Cdn/profiles resource ID."
  }
}

variable "name" {
  type        = string
  description = "Name of the origin group."
  nullable    = false

  # Azure's rule for profiles/originGroups: 1-50 alphanumerics and hyphens,
  # starting and ending alphanumeric (resource-name-rules table, Microsoft.Cdn).
  validation {
    condition     = length(var.name) <= 50 && can(regex("^[a-zA-Z0-9]+(-*[a-zA-Z0-9])*$", var.name))
    error_message = "name must be 1-50 characters of letters, digits and hyphens, starting and ending with a letter or digit."
  }
}

variable "origins" {
  type = map(object({
    host_name                      = string
    origin_host_header             = optional(string, null)
    http_port                      = optional(number, 80)
    https_port                     = optional(number, 443)
    priority                       = optional(number, 1)
    weight                         = optional(number, 1000)
    enabled                        = optional(bool, true)
    certificate_name_check_enabled = optional(bool, true)
    private_link = optional(object({
      target_resource_id = string
      group_id           = optional(string, null)
      location           = string
      request_message    = optional(string, "Front Door origin connection")
    }), null)
  }))
  description = <<-EOT
    Origins in the group, keyed by origin name.

    - `host_name`: the origin's address — for storage, the account's `blob` or
      `web` endpoint host (e.g. `example.z6.web.core.windows.net`).
    - `origin_host_header`: defaults to `host_name`, which Blob Storage, static
      websites and App Service all require.
    - `priority` (1-5) and `weight` (1-1000): failover order and traffic split.
    - `certificate_name_check_enabled`: check the origin's certificate name.
    - `private_link`: connect over Private Link (Premium only) instead of the
      origin's public endpoint.
      - `target_resource_id`: the resource to connect to — a storage account, an
        App Service, a Private Link Service.
      - `group_id`: the sub-resource, e.g. `blob` or `web` for a storage account.
        Null for a Private Link Service, which has none.
      - `location`: a region Front Door Private Link supports, the origin's own
        or the nearest one.
      - `request_message`: shown to whoever approves the connection.

    ⚠️ Front Door creates the private endpoint, but the connection must be
    approved on the target before any traffic passes. One endpoint is created
    per target, sub-resource and region within a profile, so origins sharing
    those three need one approval between them.
  EOT
  nullable    = false

  validation {
    condition     = length(var.origins) > 0
    error_message = "origins must contain at least one origin."
  }

  validation {
    condition = alltrue([
      for name in keys(var.origins) : length(name) <= 50 && can(regex("^[a-zA-Z0-9]+(-*[a-zA-Z0-9])*$", name))
    ])
    error_message = "origins keys are origin names: 1-50 characters of letters, digits and hyphens, starting and ending with a letter or digit."
  }

  validation {
    condition     = alltrue([for origin in values(var.origins) : length(origin.host_name) > 0])
    error_message = "origins host_name must not be empty."
  }

  validation {
    condition = alltrue([
      for origin in values(var.origins) :
      origin.http_port >= 1 && origin.http_port <= 65535 && origin.https_port >= 1 && origin.https_port <= 65535
    ])
    error_message = "origins http_port and https_port must be between 1 and 65535."
  }

  validation {
    condition = alltrue([
      for origin in values(var.origins) :
      origin.priority >= 1 && origin.priority <= 5 && origin.weight >= 1 && origin.weight <= 1000
    ])
    error_message = "origins priority must be 1 to 5 and weight 1 to 1000."
  }

  # Front Door does not allow public and Private Link origins in one group.
  validation {
    condition = (
      alltrue([for origin in values(var.origins) : origin.private_link == null]) ||
      alltrue([for origin in values(var.origins) : origin.private_link != null])
    )
    error_message = "origins must all use private_link or none of them — Front Door does not mix public and Private Link origins in one group."
  }

  validation {
    condition = alltrue([
      for origin in values(var.origins) :
      origin.private_link == null || can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/.+$", try(origin.private_link.target_resource_id, "")))
    ])
    error_message = "origins private_link target_resource_id must be a resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional — authentication
# -----------------------------------------------------------------------------

variable "authentication" {
  type = object({
    type                               = optional(string, "UserAssignedIdentity")
    user_assigned_identity_resource_id = optional(string, null)
    scope                              = optional(string, "https://storage.azure.com/.default")
  })
  default     = null
  description = <<-EOT
    Managed-identity origin authentication. Null sends requests unauthenticated.

    - `type`: `UserAssignedIdentity` or `SystemAssignedIdentity` — an identity of
      the PROFILE, which must already be attached to it.
    - `user_assigned_identity_resource_id`: required with `UserAssignedIdentity`.
    - `scope`: the token audience. Front Door accepts only
      `https://storage.azure.com/.default`, `api://<GUID>/.default`,
      `https://appconfig.azure.com/.default` and
      `https://appconfig-staging.azure.com/.default`.

    Front Door sends the token in `Authorization` on every request, overwriting
    any the client sent. Grant the identity the least role the origin needs —
    Storage Blob Data Reader, not Contributor — since every request through the
    route carries it. When the origin refuses anonymous access, grant the role
    BEFORE setting this, or traffic fails until it lands.

    ⚠️ Not supported with Private Link origins, and it needs an HTTPS health
    probe and routes that forward HTTPS only. Microsoft lists the feature as
    preview.
  EOT

  validation {
    condition     = var.authentication == null || contains(["UserAssignedIdentity", "SystemAssignedIdentity"], try(var.authentication.type, ""))
    error_message = "authentication.type must be UserAssignedIdentity or SystemAssignedIdentity."
  }

  validation {
    condition = var.authentication == null || (
      (try(var.authentication.type, "") == "UserAssignedIdentity") == (try(var.authentication.user_assigned_identity_resource_id, null) != null)
    )
    error_message = "authentication.user_assigned_identity_resource_id is required with UserAssignedIdentity and must be null with SystemAssignedIdentity."
  }

  validation {
    condition = var.authentication == null || can(regex(
      "^(https://storage\\.azure\\.com/\\.default|api://[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/\\.default|https://appconfig\\.azure\\.com/\\.default|https://appconfig-staging\\.azure\\.com/\\.default)$",
      try(var.authentication.scope, "")
    ))
    error_message = "authentication.scope must be one Front Door accepts: https://storage.azure.com/.default, api://<GUID>/.default, https://appconfig.azure.com/.default or https://appconfig-staging.azure.com/.default."
  }

  validation {
    condition     = var.authentication == null || alltrue([for origin in values(var.origins) : origin.private_link == null])
    error_message = "authentication is not supported on an origin group with Private Link origins."
  }

  validation {
    condition     = var.authentication == null || try(var.health_probe.protocol, "") == "Https"
    error_message = "authentication needs an HTTPS health probe: health_probe must be set with protocol Https."
  }
}

# -----------------------------------------------------------------------------
# Optional — health and load balancing
# -----------------------------------------------------------------------------

variable "health_probe" {
  type = object({
    path                = optional(string, "/")
    protocol            = optional(string, "Https")
    request_type        = optional(string, "HEAD")
    interval_in_seconds = optional(number, 100)
  })
  default     = {}
  description = <<-EOT
    Health probe settings. Null disables probing, which Front Door allows only
    while the group has a single enabled origin — and recommends then, since a
    lone origin has nowhere to fail over to.

    - `path`: probed on the origin itself, not through any route's origin path.
    - `protocol`: `Http` or `Https`.
    - `request_type`: `HEAD` or `GET`.
    - `interval_in_seconds`: 1 to 255. Every Front Door point of presence probes
      on its own, so the origin sees far more probes than this suggests.
  EOT

  validation {
    condition     = var.health_probe == null || contains(["Http", "Https"], try(var.health_probe.protocol, ""))
    error_message = "health_probe.protocol must be Http or Https."
  }

  validation {
    condition     = var.health_probe == null || contains(["GET", "HEAD"], try(var.health_probe.request_type, ""))
    error_message = "health_probe.request_type must be GET or HEAD."
  }

  validation {
    condition     = var.health_probe == null || startswith(try(var.health_probe.path, ""), "/")
    error_message = "health_probe.path must start with /."
  }

  validation {
    condition = var.health_probe == null || (
      try(var.health_probe.interval_in_seconds, 0) >= 1 &&
      try(var.health_probe.interval_in_seconds, 0) <= 255 &&
      floor(try(var.health_probe.interval_in_seconds, 0)) == try(var.health_probe.interval_in_seconds, 0)
    )
    error_message = "health_probe.interval_in_seconds must be an integer from 1 to 255."
  }

  validation {
    condition     = var.health_probe != null || length([for origin in values(var.origins) : origin if origin.enabled]) <= 1
    error_message = "health_probe can only be null while the group has at most one enabled origin."
  }
}

variable "load_balancing" {
  type = object({
    sample_size                        = optional(number, 4)
    successful_samples_required        = optional(number, 3)
    additional_latency_in_milliseconds = optional(number, 50)
  })
  default     = {}
  description = <<-EOT
    Load balancing settings.

    - `sample_size`: probe results considered per decision.
    - `successful_samples_required`: of those, how many must succeed for an
      origin to count as healthy.
    - `additional_latency_in_milliseconds`: origins within this much of the
      fastest one share traffic.
  EOT
  nullable    = false

  validation {
    condition = (
      var.load_balancing.sample_size >= 1 &&
      var.load_balancing.successful_samples_required >= 1 &&
      var.load_balancing.successful_samples_required <= var.load_balancing.sample_size &&
      var.load_balancing.additional_latency_in_milliseconds >= 0
    )
    error_message = "load_balancing needs sample_size >= 1, successful_samples_required between 1 and sample_size, and additional_latency_in_milliseconds >= 0."
  }
}

variable "session_affinity_enabled" {
  type        = bool
  default     = false
  description = "Pin a client to one origin with an affinity cookie."
  nullable    = false
}
