variable "name" {
  type        = string
  description = "Private DNS zone name (fully-qualified, e.g., `privatelink.vaultcore.azure.net`, `internal.acme.example`)."
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
  description = "Tags to apply to the private DNS zone."
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
    - a built-in role name (e.g., `Private DNS Zone Contributor`).

    Mirrors AVM's standard `role_assignments` interface block.
  EOT
  default     = {}
}
