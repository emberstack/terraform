variable "name" {
  type        = string
  description = "Public DNS zone name (fully-qualified, e.g., `dev.acme.example`)."
  nullable    = false

  validation {
    condition     = can(regex("^([a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?\\.)+[a-zA-Z]{2,}$", var.name))
    error_message = "name must be a valid fully-qualified DNS zone name."
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

variable "tags" {
  type        = map(string)
  description = "Tags to apply to the DNS zone."
  default     = {}
}

variable "soa_record" {
  type = object({
    email        = string
    expire_time  = optional(number)
    minimum_ttl  = optional(number)
    refresh_time = optional(number)
    retry_time   = optional(number)
    ttl          = optional(number)
    tags         = optional(map(string))
  })
  description = <<-EOT
    Optional SOA record overrides. `email` is required when this is set; other fields fall back to Azure defaults.

    AVM `avm-res-network-dnszone` does not expose this — emberstack does.
  EOT
  default     = null
}

variable "role_assignments" {
  type = map(object({
    role_definition_id_or_name             = string
    principal_id                           = string
    description                            = optional(string)
    skip_service_principal_aad_check       = optional(bool, false)
    condition                              = optional(string)
    condition_version                      = optional(string)
    delegated_managed_identity_resource_id = optional(string)
    principal_type                         = optional(string)
  }))
  description = <<-EOT
    Map of zone-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `DNS Zone Contributor`, `Private DNS Zone Contributor`).

    Mirrors AVM's standard `role_assignments` interface block.
  EOT
  default     = {}
}

variable "parent_zone" {
  type = object({
    zone_id         = string
    delegation_name = string
    delegation_ttl  = optional(number, 3600)
    delegation_tags = optional(map(string), {})
  })
  description = <<-EOT
    Optional parent-zone NS delegation. When set, creates an `azurerm_dns_ns_record` in the parent zone whose `records` are this zone's name servers — wiring up the subdomain delegation in one apply.

    `zone_id` is the parent zone's ARM resource ID; the parent's RG name and zone name are parsed from it.

    `delegation_name` is the subdomain label to delegate (e.g., `glb` to delegate `glb.acme.example` from `acme.example`).

    `delegation_tags` are applied to the NS delegation record. Defaults to `{}` (empty). The zone's `var.tags` are NOT inherited — set `delegation_tags` explicitly if you want tags on the delegation record.

    The deploying principal must have write access to the parent zone's RG (typically `DNS Zone Contributor`). If the parent zone is in a different subscription, configure provider aliases at the leaf level.

    AVM `avm-res-network-dnszone` does not expose this — emberstack does.
  EOT
  default     = null

  validation {
    condition     = var.parent_zone == null || can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.network/dnszones/[^/]+$", var.parent_zone.zone_id))
    error_message = "parent_zone.zone_id must be an ARM resource ID of an Azure public DNS zone."
  }
}
