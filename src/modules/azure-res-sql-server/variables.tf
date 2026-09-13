# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the Azure SQL logical server. Becomes `<name>.database.windows.net`, so it must be globally unique."
  nullable    = false

  # The server name becomes a public DNS label, so ARM restricts it to the
  # lower-case subset of the hostname alphabet. Terraform's regex engine is RE2
  # and has no lookahead, so the length half is checked separately; the
  # alternation covers the leading, trailing and consecutive hyphen rules by
  # itself.
  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 63 && can(regex("^[a-z0-9]+(-[a-z0-9]+)*$", var.name))
    error_message = "name must be 1-63 characters of lower-case letters, digits and hyphens, with no leading, trailing or consecutive hyphens."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the server should be deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the server will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

# -----------------------------------------------------------------------------
# Optional - server
# -----------------------------------------------------------------------------

variable "server_version" {
  type        = string
  default     = "12.0"
  description = "The version of the server. `12.0` is the only version Azure SQL Database accepts today."
  nullable    = false
}

variable "minimum_tls_version" {
  type        = string
  default     = "1.2"
  description = "Minimum TLS version clients must negotiate. `None` disables the floor entirely and is not a safe default."
  nullable    = false

  validation {
    condition     = contains(["None", "1.0", "1.1", "1.2", "1.3"], var.minimum_tls_version)
    error_message = "minimum_tls_version must be one of: None, 1.0, 1.1, 1.2, 1.3."
  }
}

variable "public_network_access_enabled" {
  type        = bool
  default     = false
  description = "Whether the public endpoint is reachable. Defaults to disabled, so a private endpoint is the only way in unless this is turned on deliberately."
  nullable    = false
}

variable "outbound_network_restriction_enabled" {
  type        = bool
  default     = false
  description = "Whether outbound network access from the server is restricted to approved targets. Maps to ARM `restrictOutboundNetworkAccess`."
  nullable    = false
}

variable "connection_policy" {
  type        = string
  default     = null
  description = <<-EOT
    How clients reach the server: `Default` (proxy from outside Azure, redirect
    from inside), `Proxy` (always through the gateway) or `Redirect` (straight to
    the node, lower latency, needs ports 11000-11999 open).

    Null leaves it unmanaged on Azure's own default, which is `Default`.
  EOT

  validation {
    condition     = var.connection_policy == null || contains(["Default", "Proxy", "Redirect"], var.connection_policy)
    error_message = "connection_policy must be one of: Default, Proxy, Redirect."
  }
}

variable "federated_client_id" {
  type        = string
  default     = null
  description = "Client ID of the multi-tenant application used for a cross-tenant customer-managed key. Leave null for same-tenant CMK."

  validation {
    condition     = var.federated_client_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.federated_client_id))
    error_message = "federated_client_id must be a GUID."
  }
}

# -----------------------------------------------------------------------------
# Optional - authentication
# -----------------------------------------------------------------------------

variable "administrator_login" {
  type        = string
  default     = null
  description = <<-EOT
    SQL authentication administrator username. ARM fixes this at create time and
    will not change it afterwards - a new value replaces the server.

    Required unless `entra_only_authentication_enabled` is true. When omitted,
    Azure generates a `CloudSA*` name to satisfy provisioning; that account
    cannot connect and is not a break-glass path.
  EOT
}

variable "administrator_login_password" {
  type        = string
  default     = null
  sensitive   = true
  ephemeral   = true
  description = <<-EOT
    Password for `administrator_login`.

    Declared `ephemeral`, and sent through AzAPI's `sensitive_body`, so the value
    never reaches state or the plan file. Pass it from an ephemeral source - a
    `azurerm_key_vault_secret` ephemeral resource, or a write-only variable - not
    from a resource attribute.

    Cannot be reset while Entra-only authentication is enabled.
  EOT
}

variable "administrator_login_password_version" {
  type        = string
  default     = "1"
  description = <<-EOT
    Opaque marker for the contents of `administrator_login_password`. Change it to
    any different string to force the current value to be pushed to ARM.

    Needed because the password lives in AzAPI's `sensitive_body`, which is
    excluded from plan comparison - rotating the secret without changing this
    leaves the old password on the server with a clean plan. Ignored when
    `administrator_login_password` is null.
  EOT
  nullable    = false

  validation {
    condition     = length(var.administrator_login_password_version) > 0
    error_message = "administrator_login_password_version must not be empty."
  }
}

variable "entra_administrator" {
  type = object({
    login     = string
    object_id = string
    tenant_id = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Microsoft Entra administrator for the server.

    - `login`: display label only. Azure does not resolve it, so a stale value is
      cosmetic rather than an authentication failure.
    - `object_id`: object ID of the user or group that actually gets admin.
    - `tenant_id`: defaults to the provider's tenant.

    Set as a child resource rather than inline on the server, because ARM accepts
    the inline `administrators` property at create time only.
  EOT

  validation {
    condition     = var.entra_administrator == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", try(var.entra_administrator.object_id, "")))
    error_message = "entra_administrator.object_id must be a GUID - the object ID of a user or group, not its display name."
  }

  validation {
    condition     = var.entra_administrator == null || var.entra_administrator.tenant_id == null || can(regex("^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$", var.entra_administrator.tenant_id))
    error_message = "entra_administrator.tenant_id, when supplied, must be a GUID."
  }
}

variable "entra_only_authentication_enabled" {
  type        = bool
  default     = null
  description = <<-EOT
    Whether SQL authentication is disabled, leaving Entra as the only way in.
    Null leaves the setting unmanaged.

    Requires `entra_administrator` - ARM rejects enabling this on a server with no
    Entra admin, and the module orders the two accordingly. Enabling it does not
    delete existing SQL logins; it only stops them connecting.
  EOT
}

# -----------------------------------------------------------------------------
# Optional - identity
# -----------------------------------------------------------------------------

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = {}
  description = <<-EOT
    Managed identity configuration for the server.

    - `system_assigned`: enable a system-assigned identity.
    - `user_assigned_resource_ids`: set of UAI resource IDs to attach.

    When `customer_managed_key` is set, the identity that resolves the key must be
    attached here AND named in `primary_user_assigned_identity_resource_id`.
  EOT
  nullable    = false
}

variable "primary_user_assigned_identity_resource_id" {
  type        = string
  default     = null
  description = <<-EOT
    Resource ID of the user-assigned identity the server uses by default, and the
    one TDE resolves the customer-managed key through.

    Must also appear in `managed_identities.user_assigned_resource_ids`.
  EOT
}

# -----------------------------------------------------------------------------
# Optional - encryption
# -----------------------------------------------------------------------------

variable "customer_managed_key" {
  type = object({
    key_vault_key_uri     = string
    auto_rotation_enabled = optional(bool, true)
  })
  default     = null
  description = <<-EOT
    Customer-managed key for Transparent Data Encryption. Null leaves TDE on the
    service-managed key.

    - `key_vault_key_uri`: `https://<vault>.vault.azure.net/keys/<key>` with an
      optional `/<version>` suffix. The server key's ARM name is derived from it.
    - `auto_rotation_enabled`: when true the server polls the vault and moves the
      protector to a new key version within 24 hours. Turning it off pins the
      protector to the version named in the URI.

    PASS A VERSIONED URI. Microsoft documents versionless identifiers as supported
    for Azure SQL Database, and ARM does accept one - but it NORMALISES it rather
    than storing it. `GET .../keys/<vault>_<key>` resolves to the versioned
    registration, and the server reports `keyId` in versioned form, so a
    versionless config never matches the response and diffs forever. Measured
    2026-09-13 against api-version 2025-01-01.

    Rotation is therefore handled by `auto_rotation_enabled`, not by the URI
    shape: Azure moves the protector to the newest version on its own. Keep the
    caller's key-version source (an AVM key vault module's `id`, say) refreshed
    alongside, or the declared version lags the one Azure is actually using.

    The identity in `primary_user_assigned_identity_resource_id` must already hold
    wrap/unwrap on the key before the first apply - this module does not create
    that grant, and ARM fails with `AzureKeyVaultNoServerIdentity` without it.

    SETTING THIS BACK TO NULL ON A LIVE SERVER REVERTS TDE to the service-managed
    key: `keyId` leaves the body, and an azapi update is a full replace. That is
    the honest meaning of "no customer-managed key", but it is an encryption
    change on existing data, not a no-op - detach deliberately.
  EOT

  validation {
    # The server key name is built by indexing segments of this URI, so the shape
    # is enforced here rather than left to fail on an ARM error that names
    # neither the key nor the reason.
    condition     = var.customer_managed_key == null || can(regex("^https://[^/.]+\\.[^/]+/keys/[^/]+(/[^/]+)?$", try(var.customer_managed_key.key_vault_key_uri, "")))
    error_message = "customer_managed_key.key_vault_key_uri must look like https://<vault>.vault.azure.net/keys/<key> with an optional /<version> suffix."
  }
}

# -----------------------------------------------------------------------------
# Optional - auditing
# -----------------------------------------------------------------------------

variable "auditing" {
  type = object({
    enabled                = optional(bool, true)
    log_monitoring_enabled = optional(bool, true)
    # A LIST, not a set: ARM returns this array in its own order, and a set
    # would be re-sorted into a different one and diff forever. The default is
    # the trio Azure configures when auditing is enabled from the portal -
    # sending null instead would WIPE the action groups on an existing server,
    # because an azapi update is a full replace.
    audit_actions_and_groups = optional(list(string), [
      "SUCCESSFUL_DATABASE_AUTHENTICATION_GROUP",
      "FAILED_DATABASE_AUTHENTICATION_GROUP",
      "BATCH_COMPLETED_GROUP",
    ])
    retention_in_days                    = optional(number, null)
    storage_endpoint                     = optional(string, null)
    storage_account_secondary_key_in_use = optional(bool, null)
  })
  default     = null
  description = <<-EOT
    Server-level auditing policy. Null leaves auditing unmanaged.

    - `enabled`: maps to ARM `state`.
    - `log_monitoring_enabled`: routes events to Azure Monitor. On its own this
      sends them nowhere: a diagnostic setting carrying the
      `SQLSecurityAuditEvents` category must also exist on the server's `master`
      DATABASE. That setting is a different scope from `diagnostic_settings` here
      and is the caller's to create.
    - `audit_actions_and_groups`: null lets Azure apply its default set.
    - `storage_endpoint` / `retention_in_days`: only for blob-storage auditing.
  EOT
}

# -----------------------------------------------------------------------------
# Optional - networking
# -----------------------------------------------------------------------------

variable "firewall_rules" {
  type = map(object({
    name             = optional(string, null)
    start_ip_address = string
    end_ip_address   = string
  }))
  default     = {}
  description = <<-EOT
    Server firewall rules keyed by stable name. `name` defaults to the map key.

    A rule with both addresses set to `0.0.0.0` is not a literal range - it is the
    "Allow Azure services and resources to access this server" switch, and opens
    the server to every Azure tenant.
  EOT
  nullable    = false
}

variable "virtual_network_rules" {
  type = map(object({
    name                                 = optional(string, null)
    subnet_resource_id                   = string
    ignore_missing_vnet_service_endpoint = optional(bool, false)
  }))
  default     = {}
  description = <<-EOT
    Virtual network rules keyed by stable name. `name` defaults to the map key.

    The subnet needs the `Microsoft.Sql` service endpoint. Set
    `ignore_missing_vnet_service_endpoint` to create the rule before the endpoint
    exists - the rule stays inert until it does.
  EOT
  nullable    = false
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
    subresource_name                        = optional(string, "sqlServer")
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

    `subresource_name` is `sqlServer` for the database endpoint; use
    `sqlOnDemand` for the serverless SQL endpoint on a Synapse workspace.

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
# Optional - access
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
    Role assignments scoped to the server, keyed by stable name.

    `role_definition_id_or_name` accepts either a role name (e.g. `"Reader"`) or
    a full role definition resource ID. Auto-routed by the leading `/`.

    `name` is the assignment's ARM name (a GUID). Leave it unset - a random UUID is
    generated - unless you are adopting an assignment that already exists, where the
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
# Optional - diagnostics
# -----------------------------------------------------------------------------

variable "diagnostic_settings" {
  type = map(object({
    name                                     = optional(string, null)
    log_categories                           = optional(map(bool), {})
    log_groups                               = optional(map(bool), { allLogs = true })
    metric_categories                        = optional(map(bool), { AllMetrics = true })
    log_analytics_destination_type           = optional(string, "Dedicated")
    workspace_resource_id                    = optional(string, null)
    storage_account_resource_id              = optional(string, null)
    event_hub_authorization_rule_resource_id = optional(string, null)
    event_hub_name                           = optional(string, null)
    marketplace_partner_resource_id          = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Diagnostic settings on the SERVER, keyed by stable name.

    Audit events are not emitted at this scope. `SQLSecurityAuditEvents` is a
    category of the server's `master` database, so shipping audit logs needs a
    diagnostic setting there as well as `auditing.log_monitoring_enabled` here.

    Exactly one destination must be set per entry.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional - protection
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
    - `name`: optional. Defaults to `lock-<server-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

# -----------------------------------------------------------------------------
# Optional - metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the server."
}
