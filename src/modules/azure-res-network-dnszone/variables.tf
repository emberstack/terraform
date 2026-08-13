# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Public DNS zone name (fully-qualified, e.g., `dev.acme.example`)."
  nullable    = false

  # Azure's rule for dnsZones: 1-63 characters total, 2 to 34 dot-separated labels,
  # each label made of alphanumerics, underscores and hyphens. Checked 2026-08-13
  # against the resource-name-rules table.
  #
  # The whole name is length-bounded as well as each label, so a 64-character zone is
  # rejected here rather than at ARM. Underscores are legal and the final label need
  # not be alphabetic, so names like `db.k8s1` pass.
  #
  # The no-leading and no-trailing hyphen rule is stricter than that table: it comes
  # from DNS itself (RFC 1123 — labels start and end alphanumeric), and is enforced
  # deliberately.
  validation {
    condition = (
      length(var.name) >= 1 && length(var.name) <= 63 &&
      length(split(".", var.name)) >= 2 && length(split(".", var.name)) <= 34 &&
      alltrue([for label in split(".", var.name) : can(regex("^[A-Za-z0-9_]([A-Za-z0-9_-]*[A-Za-z0-9_])?$", label))])
    )
    error_message = "name must be 1–63 characters across 2–34 dot-separated labels, each containing only letters, digits, underscores and hyphens, and not starting or ending with a hyphen (e.g. `dev.example.com`)."
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
    minimum_ttl  = optional(number, 300)
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

    AVM `avm-res-network-dnszone` does not expose this — emberstack does.
  EOT
}

variable "parent_zone" {
  type = object({
    zone_id         = string
    delegation_name = string
    delegation_ttl  = optional(number, 3600)
    delegation_tags = optional(map(string), {})
  })
  default     = null
  description = <<-EOT
    Optional parent-zone NS delegation. When set, creates an NS record in the parent zone whose entries are this zone's name servers — wiring up the subdomain delegation in one apply.

    `zone_id` is the parent zone's ARM resource ID; the parent's RG name and zone name are parsed from it.

    `delegation_name` is the subdomain label to delegate (e.g., `glb` to delegate `glb.acme.example` from `acme.example`).

    `delegation_tags` are applied to the NS delegation record. Defaults to `{}` (empty). The zone's `var.tags` are NOT inherited — set `delegation_tags` explicitly if you want tags on the delegation record.

    The deploying principal must have write access to the parent zone's RG (typically `DNS Zone Contributor`). If the parent zone is in a different subscription, configure provider aliases at the leaf level.

    AVM `avm-res-network-dnszone` does not expose this — emberstack does.
  EOT

  validation {
    condition     = var.parent_zone == null || can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/dnszones/[^/]+$", var.parent_zone.zone_id))
    error_message = "parent_zone.zone_id must be an ARM resource ID of an Azure public DNS zone."
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
    Map of zone-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `DNS Zone Contributor`), resolved by a subscription-scope lookup.

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
  description = "Tags to apply to the DNS zone."
}
