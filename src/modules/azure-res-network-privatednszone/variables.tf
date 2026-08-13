# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Private DNS zone name (fully-qualified, e.g., `privatelink.vaultcore.azure.net`, `internal.acme.example`)."
  nullable    = false

  # Azure's rule for privateDnsZones: 1-63 characters total, 2 to 34 dot-separated
  # labels, each label made of alphanumerics, underscores and hyphens. Single-label
  # private zones are explicitly unsupported, which the 2-label floor covers.
  # Checked 2026-08-13 against the resource-name-rules table and the private DNS
  # zone restrictions page.
  #
  # The regex this replaced was wrong in both directions. It bounded each label but
  # never the whole name, so a 64-character zone passed here and failed at ARM. And
  # it was stricter than Azure in requiring an all-alphabetic final label and
  # disallowing underscores, so it rejected legal names like `db.k8s1`.
  #
  # The no-leading and no-trailing hyphen rule is not in that table — it is DNS
  # itself (RFC 1123: labels start and end alphanumeric). The old regex enforced it,
  # so it is kept deliberately rather than loosened away with the rest.
  validation {
    condition = (
      length(var.name) >= 1 && length(var.name) <= 63 &&
      length(split(".", var.name)) >= 2 && length(split(".", var.name)) <= 34 &&
      alltrue([for label in split(".", var.name) : can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]*[A-Za-z0-9_])?$", label))])
    )
    error_message = "name must be 1–63 characters across 2–34 dot-separated labels, each containing only letters, digits, underscores and hyphens, and not starting or ending with a hyphen (e.g. `internal.example.com`). Single-label zones are not supported by Azure Private DNS."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the zone will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional — zone configuration
# -----------------------------------------------------------------------------

variable "soa_record" {
  type = object({
    email        = string
    expire_time  = optional(number, 2419200)
    minimum_ttl  = optional(number, 10)
    refresh_time = optional(number, 3600)
    retry_time   = optional(number, 300)
    ttl          = optional(number, 3600)
    tags         = optional(map(string), {})
  })
  default     = null
  description = <<-EOT
    Optional SOA record overrides. `email` is required when this is set; every other field defaults to
    Azure's own default for that timer. The defaults are restated here rather than left null because
    the SOA record is written with a full PUT — an omitted field resets the server-side value.
  EOT
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
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
    principal_type                         = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Map of zone-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Private DNS Zone Contributor`), resolved by a subscription-scope lookup.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is generated — unless you
    are adopting an assignment that already exists, where the existing GUID must be supplied to avoid a
    destroy-and-recreate.

    `skip_service_principal_aad_check` is accepted for interface compatibility and has no effect. ARM's
    equivalent is `principalType`, which this module already exposes: set
    `principal_type = "ServicePrincipal"` so ARM skips the directory lookup that fails on a principal
    created moments earlier.

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
  description = "Tags to apply to the private DNS zone."
}
