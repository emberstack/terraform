# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the private endpoint."
  nullable    = false

  # 2-64 characters, "Alphanumerics, underscores, periods, and hyphens. Start
  # with alphanumeric. End with alphanumeric or underscore." Checked 2026-08-24
  # against resource-name-rules, Microsoft.Network/privateEndpoints. The length
  # half is checked separately so the pattern stays RE2-compatible.
  validation {
    condition     = length(var.name) >= 2 && length(var.name) <= 64 && can(regex("^[A-Za-z0-9][A-Za-z0-9._-]*[A-Za-z0-9_]$", var.name))
    error_message = "name must be 2–64 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the private endpoint should be deployed. Must match the region of the virtual network holding `subnet_resource_id`."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the private endpoint will be created. Mirrors AVM `resource_group_name`. Resolved in the subscription of `subnet_resource_id`, not the provider's — a private endpoint must live in the same subscription as its virtual network."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the subnet the private endpoint attaches to. Its subscription also determines where `resource_group_name` is resolved."
  nullable    = false

  validation {
    condition     = startswith(var.subnet_resource_id, "/subscriptions/") && can(regex("/subnets/[^/]+$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be a full subnet resource ID, of the form /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "private_connection_resource_id" {
  type        = string
  default     = null
  description = "Resource ID of the resource the endpoint connects to — a Private Link Service, or a PaaS resource that publishes private-link group IDs. May sit in a different subscription or tenant than the endpoint itself. Mutually exclusive with `private_connection_resource_alias`."

  validation {
    condition     = var.private_connection_resource_id == null || startswith(coalesce(var.private_connection_resource_id, "x"), "/subscriptions/")
    error_message = "private_connection_resource_id must be a full ARM resource ID beginning with /subscriptions/. To connect by alias instead, use private_connection_resource_alias."
  }

  validation {
    condition     = (var.private_connection_resource_id == null) != (var.private_connection_resource_alias == null)
    error_message = "Set exactly one of private_connection_resource_id or private_connection_resource_alias."
  }
}

variable "private_connection_resource_alias" {
  type        = string
  default     = null
  description = <<-EOT
    Alias of the private link service to connect to, e.g.
    `myservice.<guid>.<region>.azure.privatelinkservice`. Mutually exclusive with
    `private_connection_resource_id`.

    An alias is what a service owner publishes when the consumer has no read access to
    the underlying resource — the usual case across a tenant boundary, and what
    CloudAMQP's `cloudamqp_vpc_connect` hands back. ARM carries both forms in the same
    `privateLinkServiceId` property, so this is a naming distinction rather than a
    behavioural one; only the accepted string shape differs.
  EOT

  validation {
    condition     = var.private_connection_resource_alias == null || can(regex("\\.azure\\.privatelinkservice$", coalesce(var.private_connection_resource_alias, "")))
    error_message = "private_connection_resource_alias must be a private link service alias ending in .azure.privatelinkservice."
  }
}

# -----------------------------------------------------------------------------
# Optional — connection
# -----------------------------------------------------------------------------

variable "is_manual_connection" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether the connection request needs the target owner's approval.

    `false` places the connection in ARM's `privateLinkServiceConnections` and it is
    approved on creation — only possible when the caller holds write access on the
    target. `true` places it in `manualPrivateLinkServiceConnections`, which applies
    successfully and leaves the endpoint at `Pending` until the owner approves. Across
    a tenant boundary — MongoDB Atlas, Snowflake, Databricks and similar — manual is
    the only path.

    Flipping this on an existing endpoint moves the connection between the two arrays
    and re-raises it for approval.
  EOT
  nullable    = false
}

variable "request_message" {
  type        = string
  default     = null
  description = "Message shown to the target's owner alongside the approval request. Only read when `is_manual_connection = true`. ARM restricts it to 140 characters."

  validation {
    condition     = var.request_message == null || length(coalesce(var.request_message, "")) <= 140
    error_message = "request_message is restricted to 140 characters by ARM."
  }

  validation {
    condition     = var.request_message == null || var.is_manual_connection
    error_message = "request_message is only read on a manual connection. Set is_manual_connection = true, or leave request_message null."
  }
}

variable "subresource_names" {
  type        = list(string)
  default     = []
  description = <<-EOT
    Group IDs the endpoint connects to on the target — ARM's `groupIds`, AVM's
    `subresource_names`. A PaaS target requires exactly one (`blob`, `sqlServer`,
    `registry`, …).

    Leave empty when the target is a Private Link Service: a PLS publishes no group
    IDs, which is why `az network private-endpoint create` takes no `--group-id` for
    one.
  EOT
  nullable    = false
}

variable "private_service_connection_name" {
  type        = string
  default     = null
  description = "Name of the private link service connection. Defaults to `<name>-psc`. When the target's owner identifies connections by name — Atlas matches on it — set this explicitly rather than taking the default."
}

# -----------------------------------------------------------------------------
# Optional — DNS
# -----------------------------------------------------------------------------

variable "private_dns_zone_resource_ids" {
  type        = set(string)
  default     = []
  description = "Private DNS zones to publish the endpoint's records into. Each config in the zone group is named after its zone. No records appear while a manual connection is still `Pending`."
  nullable    = false
}

variable "private_dns_zone_group_name" {
  type        = string
  default     = "default"
  description = "Name of the private DNS zone group. Only used when `private_dns_zone_resource_ids` is non-empty."
  nullable    = false

  validation {
    condition     = length(var.private_dns_zone_group_name) > 0
    error_message = "private_dns_zone_group_name must not be empty."
  }
}

variable "manage_dns_zone_group" {
  type        = bool
  default     = true
  description = "Whether the module manages the private DNS zone group. Set to false to manage it externally (e.g. via Azure Policy)."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — networking
# -----------------------------------------------------------------------------

variable "network_interface_name" {
  type        = string
  default     = null
  description = "Custom name for the network interface ARM creates for the endpoint. Defaults to an ARM-generated name."
}

variable "application_security_group_associations" {
  type        = map(string)
  default     = {}
  description = "Application security groups the endpoint's IP configuration joins, keyed by stable name. ARM keeps these in the endpoint body, so there is no separate association resource."
  nullable    = false
}

variable "ip_configurations" {
  type = map(object({
    name               = string
    private_ip_address = string
    subresource_name   = optional(string, null)
    member_name        = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Static IP allocations for the endpoint, keyed by stable name. Leave empty to let
    ARM allocate dynamically from the subnet.

    `subresource_name` and `member_name` identify which of the target's members an
    address belongs to, and are required only where the target exposes more than one.
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
    Role assignments scoped to the private endpoint, keyed by stable name.

    `role_definition_id_or_name` accepts either a role name (e.g. `"Reader"`) or a full
    role-definition resource ID. Names resolve against the roleDefinitions catalogue of
    the provider's subscription, so a custom role defined elsewhere must be passed as an ID.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal
    or a managed identity, so ARM skips the directory lookup that fails on a principal
    created moments earlier.
  EOT
  nullable    = false
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
    - `name`: optional. Defaults to `lock-<name>`.
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
  description = "Tags applied to the private endpoint."
}
