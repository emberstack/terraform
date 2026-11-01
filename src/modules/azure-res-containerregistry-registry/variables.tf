# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the container registry. Globally unique; it becomes the `<name>.azurecr.io` login server."
  nullable    = false

  validation {
    condition     = can(regex("^[A-Za-z0-9]{5,50}$", var.name))
    error_message = "name must be 5–50 letters and digits, with no hyphens."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the registry should be deployed. Its home replica lives here."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the registry will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional — registry
# -----------------------------------------------------------------------------

variable "sku" {
  type        = string
  default     = "Premium"
  description = <<-EOT
    Service tier: `Basic`, `Standard` or `Premium`. Default: `Premium`, the only
    tier with private endpoints, network rules, customer-managed keys,
    geo-replication, dedicated data endpoints and the quarantine, retention and
    trust policies.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Basic", "Standard", "Premium"], var.sku)
    error_message = "sku must be one of: Basic, Standard, Premium."
  }
}

variable "admin_enabled" {
  type        = bool
  default     = false
  description = "Whether the admin user (a shared username and password) is enabled. Default: false."
  nullable    = false
}

variable "anonymous_pull_enabled" {
  type        = bool
  default     = false
  description = "Whether unauthenticated pulls are allowed. Default: false."
  nullable    = false
}

variable "data_endpoint_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether the registry serves layer blobs from a dedicated regional data
    endpoint (`<name>.<region>.data.azurecr.io`) rather than shared storage.
    Premium only. Default: false.

    With private endpoints, each data endpoint takes an address of its own in the
    endpoint's subnet and a record of its own in the private DNS zone.
  EOT
  nullable    = false
}

variable "zone_redundancy_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether the home replica is zone-redundant. Default: true, as in AVM.

    Set at creation only — ARM rejects a change on an existing registry.
  EOT
  nullable    = false
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether the registry is reachable from the public internet. Default: false —
    the opposite of AVM. A registry is normally reached over a private endpoint,
    so closed is the posture to fall into by accident.
  EOT
  nullable    = false
}

variable "network_rule_set" {
  type = object({
    default_action = optional(string, "Deny")
    ip_rules       = optional(list(string), [])
  })
  default     = {}
  description = <<-EOT
    Public network rules, consulted only while public network access is enabled.
    Premium only, and left out of the body on the other tiers.

    - `default_action`: `Allow` or `Deny`. Default: `Deny`.
    - `ip_rules`: IPv4 addresses or CIDR ranges allowed through a `Deny`.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Allow", "Deny"], var.network_rule_set.default_action)
    error_message = "network_rule_set.default_action must be Allow or Deny."
  }
}

variable "network_rule_bypass_option" {
  type        = string
  default     = "AzureServices"
  description = <<-EOT
    Whether trusted Azure services reach the registry past its network rules.
    Default: `AzureServices`. Defender for Containers and Security Center scan
    through this bypass, not through the private endpoints, so `None` blinds them
    on a registry with public access disabled.
  EOT
  nullable    = false

  validation {
    condition     = contains(["AzureServices", "None"], var.network_rule_bypass_option)
    error_message = "network_rule_bypass_option must be AzureServices or None."
  }
}

variable "network_rule_bypass_allowed_for_tasks" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether ACR Tasks may reach a network-restricted registry through the trusted
    services bypass. Default: false.

    AVM `avm-res-containerregistry-registry` does not expose this — emberstack does.
  EOT
  nullable    = false
}

variable "role_assignment_mode" {
  type        = string
  default     = "LegacyRegistryPermissions"
  description = <<-EOT
    Which role model the registry honours for data-plane access.

    - `LegacyRegistryPermissions` (default; the portal's "RBAC Registry
      Permissions"): `AcrPull`, `AcrPush` and `AcrDelete` grant data access, and
      so do `Owner`, `Contributor` and `Reader`.
    - `AbacRepositoryPermissions`: the `Container Registry Repository *` roles
      grant data access, optionally scoped to repositories by condition.

    Sent on every write, so the mode cannot move by an unrelated change. Moving
    to ABAC stops the registry honouring every `Acr*` assignment at once —
    including an AKS kubelet's `AcrPull` — so assign the replacement roles first.

    AVM `avm-res-containerregistry-registry` does not expose this — emberstack does.
  EOT
  nullable    = false

  validation {
    condition     = contains(["LegacyRegistryPermissions", "AbacRepositoryPermissions"], var.role_assignment_mode)
    error_message = "role_assignment_mode must be LegacyRegistryPermissions or AbacRepositoryPermissions."
  }
}

# -----------------------------------------------------------------------------
# Optional — policies
# -----------------------------------------------------------------------------

variable "export_policy_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether artifacts may leave the registry by import into another registry or
    by pipeline export. Default: true. Turning it off requires Premium with public
    network access disabled.
  EOT
  nullable    = false
}

variable "quarantine_policy_enabled" {
  type        = bool
  default     = false
  description = "Whether pushed images are quarantined until a scanner releases them. Premium only. Default: false."
  nullable    = false
}

variable "retention_policy" {
  type = object({
    enabled = optional(bool, false)
    days    = optional(number, 7)
  })
  default     = {}
  description = <<-EOT
    Retention of untagged manifests. Premium only.

    - `enabled`: whether untagged manifests are deleted. Default: false.
    - `days`: how long an untagged manifest is kept first, 0–365. Default: 7.
  EOT
  nullable    = false

  validation {
    condition     = var.retention_policy.days >= 0 && var.retention_policy.days <= 365 && floor(var.retention_policy.days) == var.retention_policy.days
    error_message = "retention_policy.days must be a whole number of days from 0 to 365."
  }
}

variable "trust_policy_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether Docker Content Trust (Notary v1) signing is enabled. Premium only.
    Default: false. Microsoft is retiring Content Trust; Notary Project signing
    does not need this policy.
  EOT
  nullable    = false
}

variable "azure_ad_authentication_as_arm_policy_enabled" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether the registry accepts Entra tokens issued for the ARM audience.
    Default: true, ARM's own default. Turning it off accepts only tokens issued
    for the registry audience.

    AVM `avm-res-containerregistry-registry` does not expose this — emberstack does.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — identity and encryption
# -----------------------------------------------------------------------------

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    Managed identity configuration for the registry.

    - `system_assigned`: enable a system-assigned identity.
    - `user_assigned_resource_ids`: set of UAI resource IDs to attach.

    The identity named by `customer_managed_key` must be one of the user-assigned
    identities here.
  EOT
  nullable    = false
}

variable "customer_managed_key" {
  type = object({
    key_vault_key_uri                  = string
    user_assigned_identity_resource_id = string
  })
  default     = null
  description = <<-EOT
    Customer-managed key encryption. Premium only, and fixed at creation: a
    registry created without one cannot take one later, and one created with one
    cannot drop it.

    - `key_vault_key_uri`: `https://<vault>.vault.azure.net/keys/<key>`, with an
      optional `/<version>` suffix. Versionless turns on ACR's own rotation: it
      moves to a new key version within an hour of one appearing. A version pins
      the key.
    - `user_assigned_identity_resource_id`: the identity ACR reads the key as.
      It must also be listed in `managed_identities.user_assigned_resource_ids`,
      and hold wrap/unwrap on the key (`Key Vault Crypto Service Encryption User`)
      before the first apply — this module does not create that grant.

    Moving to another identity is an update: attach the new identity and grant it
    first, point this input at it, and detach the old identity only after that has
    been applied.

    Setting this back to null on a CMK registry leaves the encryption in place —
    ARM cannot disable it — and stops Terraform tracking it.
  EOT

  validation {
    condition     = var.customer_managed_key == null || can(regex("^https://[^/.]+\\.[^/]+/keys/[^/]+(/[^/]+)?$", try(var.customer_managed_key.key_vault_key_uri, "")))
    error_message = "customer_managed_key.key_vault_key_uri must be https://<vault host>/keys/<key> with an optional /<version>."
  }

  validation {
    condition = var.customer_managed_key == null || contains(
      [for id in var.managed_identities.user_assigned_resource_ids : lower(id)],
      lower(try(var.customer_managed_key.user_assigned_identity_resource_id, ""))
    )
    error_message = "customer_managed_key.user_assigned_identity_resource_id must also be listed in managed_identities.user_assigned_resource_ids."
  }
}

# -----------------------------------------------------------------------------
# Optional — replication and content
# -----------------------------------------------------------------------------

variable "georeplications" {
  type = map(object({
    regional_endpoint_enabled = optional(bool, true)
    zone_redundancy_enabled   = optional(bool, true)
    tags                      = optional(map(string), null)
  }))
  default     = {}
  description = <<-EOT
    Geo-replicas keyed by region name (`northeurope`), which also names the
    replication. The home region is the registry itself and must not be listed.
    Premium only.

    - `regional_endpoint_enabled`: whether the replica serves traffic on its own
      regional endpoint. Default: true.
    - `zone_redundancy_enabled`: set at creation only. Default: true, as in AVM.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for region in keys(var.georeplications) : can(regex("^[a-z0-9]{5,50}$", region)) && region != lower(replace(var.location, " ", ""))])
    error_message = "Every georeplications key must be a region name in ARM's form (`northeurope`) other than the registry's own location."
  }
}

variable "import_images" {
  type = map(object({
    source_registry_uri = string
    source_image        = string
    target_tags         = optional(list(string), null)
  }))
  default     = {}
  description = <<-EOT
    Images seeded through ARM's `importImage` action, keyed by stable name.

    - `source_registry_uri`: the registry to copy from, such as `ghcr.io`.
    - `source_image`: `repository[:tag]` or `repository@digest` in that registry.
    - `target_tags`: `repository[:tag]` names to write. Null keeps the source
      name and tag.

    Each key imports once, when it first appears. ARM refuses to overwrite an
    existing tag, so later edits to an entry are ignored rather than re-run;
    re-key the entry to import again. A registry that is replaced is re-seeded.

    AVM `avm-res-containerregistry-registry` does not expose this — emberstack does.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — networking
# -----------------------------------------------------------------------------

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
    subresource_name                        = optional(string, "registry")
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
    Private endpoints keyed by stable name. Shape mirrors AVM standard. Premium
    only.

    A `registry` endpoint takes one address for the login server and one more for
    each data endpoint, so static `ip_configurations` need an entry per address:
    `member_name` is `registry` for the login server and
    `registry_data_<region>` for each data endpoint.

    Keys of this map, and of each nested `role_assignments` map, must be snake_case
    handles: a per-endpoint role assignment's state address is the two keys joined
    with `-`, so the keys themselves must not contain that separator.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal
    or a managed identity, so ARM skips the directory lookup that fails on a principal
    created moments earlier.
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
    Role assignments scoped to the registry, keyed by stable name.

    `role_definition_id_or_name` accepts either a role name (e.g. `"AcrPull"`) or
    a full role definition resource ID. Auto-routed by the leading `/`. Which
    roles grant data access depends on `role_assignment_mode`.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is
    generated — unless you are adopting an assignment that already exists, where the
    existing GUID must be supplied to avoid a destroy-and-recreate.

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
# Optional — diagnostics
# -----------------------------------------------------------------------------

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(map(bool), {})
    log_groups                               = optional(map(bool), { allLogs = true })
    metric_categories                        = optional(map(bool), { AllMetrics = true })
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the registry, keyed by stable name.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan. A registry has two log categories,
    `ContainerRegistryLoginEvents` and `ContainerRegistryRepositoryEvents`, and
    one metric category, `AllMetrics`.

    There is no `log_analytics_destination_type`: a registry writes only to its
    resource-specific tables (`ContainerRegistryLoginEvents`,
    `ContainerRegistryRepositoryEvents`, `AzureMetrics`), and ARM keeps no
    destination type for it.

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
    - `name`: optional. Defaults to `lock-<registry-name>`.
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
  description = "Tags applied to the registry."
}
