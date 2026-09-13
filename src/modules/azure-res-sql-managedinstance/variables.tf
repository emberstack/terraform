# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the managed instance. Becomes `<name>.<dns-zone>.database.windows.net`, where the DNS zone is assigned by Azure."
  nullable    = false

  # The instance name becomes a public DNS label, so ARM restricts it to the
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
  description = "Azure region where the managed instance should be deployed. Must be the region of `subnet_resource_id`."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the managed instance will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "subnet_resource_id" {
  type        = string
  description = <<-EOT
    Resource ID of the delegated subnet the instance is injected into. A managed
    instance has no public endpoint to fall back on - this is the network.

    The subnet must be delegated to `Microsoft.Sql/managedInstances` AND carry
    both a route table and a network security group before ARM will report it
    "Ready for Managed Instance". Neither association is created here, and a
    create against an unprepared subnet fails after ARM has already begun
    provisioning - which on this resource is measured in hours, not seconds.

    FORCES REPLACEMENT. An instance cannot be moved between subnets.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be a full subnet resource ID."
  }
}

variable "sku_name" {
  type        = string
  description = <<-EOT
    Service tier and hardware generation, spelled EXACTLY as the ARM SKU
    catalogue spells it.

    ⚠️ THIS IS NOT THE azurerm SPELLING. The azurerm provider accepts aliases of
    its own and translates them; AzAPI sends what it is given and compares what
    comes back, so an alias diffs on every plan forever. Most visibly
    `BC_Gen8IH` (azurerm) is `BC_G8IH` in ARM - while `GP_Gen5` and `BC_Gen5`
    keep their `Gen`, because that is how the catalogue spells those.

    The accepted values below are the SKUs the capabilities API reports for
    `Microsoft.Sql/locations/<region>/capabilities`, measured 2026-09-13:

    | tier             | family | sku       |
    |------------------|--------|-----------|
    | GeneralPurpose   | Gen5   | `GP_Gen5` |
    | GeneralPurpose   | Gen8IH | `GP_G8IH` |
    | GeneralPurpose   | Gen8IM | `GP_G8IM` |
    | BusinessCritical | Gen5   | `BC_Gen5` |
    | BusinessCritical | Gen8IH | `BC_G8IH` |
    | BusinessCritical | Gen8IM | `BC_G8IM` |

    `tier` and `family` are NOT sent - ARM derives both from the name, and an
    omitted property is not compared, so there is nothing here to drift.

    FORCES REPLACEMENT across hardware generations. vCores and storage scale in
    place; the family underneath them does not.
  EOT
  nullable    = false

  validation {
    condition     = contains(["GP_Gen5", "GP_G8IH", "GP_G8IM", "BC_Gen5", "BC_G8IH", "BC_G8IM"], var.sku_name)
    error_message = <<-EOT
      sku_name must be one of: GP_Gen5, GP_G8IH, GP_G8IM, BC_Gen5, BC_G8IH, BC_G8IM.

      If you arrived here from an azurerm configuration, note that the provider's
      `BC_Gen8IH` / `GP_Gen8IH` / `BC_Gen8IM` / `GP_Gen8IM` are azurerm aliases,
      not ARM SKU names. Drop the `en` from `Gen8`: `BC_Gen8IH` is `BC_G8IH`.
      The Gen5 SKUs are unchanged.
    EOT
  }
}

variable "vcores" {
  type        = number
  description = <<-EOT
    Number of vCores. Sent as both `properties.vCores` and `sku.capacity`, which
    ARM keeps in step.

    Scales in place - a change here does not replace the instance, but it is an
    online operation that takes time and ends in a failover.
  EOT
  nullable    = false

  validation {
    condition     = var.vcores > 0 && floor(var.vcores) == var.vcores
    error_message = "vcores must be a positive whole number. Valid values depend on the SKU family."
  }
}

variable "storage_size_in_gb" {
  type        = number
  description = <<-EOT
    Storage allocated to the instance, in GB.

    ARM reports a minimum of 32 GB and a scale step of 32 GB for every SKU
    family (capabilities API, measured 2026-09-13). The maximum depends on tier,
    family and vCore count and is not enforced here.

    Scales in place.
  EOT
  nullable    = false

  validation {
    condition     = var.storage_size_in_gb >= 32 && var.storage_size_in_gb % 32 == 0
    error_message = "storage_size_in_gb must be at least 32 and a multiple of 32."
  }
}

# -----------------------------------------------------------------------------
# Optional - instance
# -----------------------------------------------------------------------------

variable "license_type" {
  type        = string
  default     = "LicenseIncluded"
  description = "`LicenseIncluded` pays for the SQL Server licence in the vCore price; `BasePrice` applies Azure Hybrid Benefit against a licence you already own."
  nullable    = false

  validation {
    condition     = contains(["LicenseIncluded", "BasePrice"], var.license_type)
    error_message = "license_type must be one of: LicenseIncluded, BasePrice."
  }
}

variable "collation" {
  type        = string
  default     = "SQL_Latin1_General_CP1_CI_AS"
  description = "Server-level collation. FORCES REPLACEMENT - ARM fixes it at create time."
  nullable    = false
}

variable "timezone_id" {
  type        = string
  default     = "UTC"
  description = "Windows time-zone identifier, e.g. `UTC` or `W. Europe Standard Time`. FORCES REPLACEMENT - ARM fixes it at create time."
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

variable "proxy_override" {
  type        = string
  default     = null
  description = <<-EOT
    How clients reach the instance: `Proxy` (always through the gateway, port
    1433 only), `Redirect` (straight to the node after the handshake, lower
    latency, needs ports 11000-11999 open to the subnet) or `Default`.

    ⚠️ DO NOT CONFIGURE `Default`. ARM resolves it on write and reports back the
    value it resolved to - `Redirect` on every instance measured 2026-09-13 - so
    a config saying `Default` never matches the response and the setting diffs
    on every plan, forever. Name the resolved value instead, and size the
    network path for it: Redirect needs 11000-11999 open to the subnet, not just
    1433. Null leaves the setting unmanaged.
  EOT

  validation {
    condition     = var.proxy_override == null || contains(["Default", "Proxy", "Redirect"], var.proxy_override)
    error_message = "proxy_override must be one of: Default, Proxy, Redirect."
  }
}

variable "public_data_endpoint_enabled" {
  type        = bool
  default     = false
  description = "Whether the instance is additionally reachable on the public data endpoint (port 3342). Defaults to off, leaving the VNet-local endpoint as the only way in."
  nullable    = false
}

variable "zone_redundant_enabled" {
  type        = bool
  default     = false
  description = "Whether the instance is spread across availability zones. Support depends on tier, family and region; ARM rejects the combinations it does not offer."
  nullable    = false
}

variable "backup_storage_redundancy" {
  type        = string
  default     = null
  description = <<-EOT
    Redundancy of the backup storage, sent as `requestedBackupStorageRedundancy`.
    Null leaves it on Azure's regional default.

    ⚠️ THESE ARE THE ARM VALUES, not the storage-account SKU names azurerm takes.
    `GZRS` in an azurerm configuration is `GeoZone` here, `LRS` is `Local`,
    `ZRS` is `Zone`, `RAGRS`/`GRS` is `Geo`. ARM reports the applied value back
    as `currentBackupStorageRedundancy`, which this module does not send.
  EOT

  validation {
    condition     = var.backup_storage_redundancy == null || contains(["Geo", "GeoZone", "Local", "Zone"], var.backup_storage_redundancy)
    error_message = "backup_storage_redundancy must be one of: Geo, GeoZone, Local, Zone. (An azurerm `GZRS` is `GeoZone` here.)"
  }
}

variable "requested_logical_availability_zone" {
  type        = string
  default     = null
  description = "Preferred availability zone for a non-zone-redundant instance: `NoPreference`, `1`, `2` or `3`. Null leaves it unmanaged."

  validation {
    condition     = var.requested_logical_availability_zone == null || contains(["NoPreference", "1", "2", "3"], var.requested_logical_availability_zone)
    error_message = "requested_logical_availability_zone must be one of: NoPreference, 1, 2, 3."
  }
}

variable "maintenance_configuration_resource_id" {
  type        = string
  default     = null
  description = <<-EOT
    Resource ID of the public maintenance configuration governing when Azure
    patches the instance. Null leaves it on the default window.

    Public configurations are subscription-scoped IDs of the form
    `/subscriptions/<sub>/providers/Microsoft.Maintenance/publicMaintenanceConfigurations/<name>`,
    where `<name>` is `SQL_Default` or a regional window such as
    `SQL_WestEurope_MI_1`.
  EOT
}

variable "general_purpose_v2_enabled" {
  type        = bool
  default     = null
  description = <<-EOT
    Whether the instance runs on next-generation General Purpose, which decouples
    IOPS and throughput from the storage size. Null leaves it unmanaged.

    Only meaningful on a `GP_*` SKU. `storage_iops` and `storage_throughput_mbps`
    are only settable while this is on.

    Sent in the CREATE body, so a new instance is born on the tier asked for.
    That matters: ARM refuses a v1 -> v2 conversion that does not also name the
    target edition, so an instance created as v1 cannot be flipped by this
    property alone.
  EOT
}

variable "database_format" {
  type        = string
  default     = null
  description = <<-EOT
    Database engine format: `AlwaysUpToDate` to track the newest engine, or
    `SQLServer2022` to pin the 2022 feature set. Null leaves it unmanaged.

    ⚠️ CHANGING `AlwaysUpToDate` -> `SQLServer2022` FORCES REPLACEMENT. The
    reverse direction is in place.
  EOT

  validation {
    condition     = var.database_format == null || contains(["AlwaysUpToDate", "SQLServer2022"], var.database_format)
    error_message = "database_format must be one of: AlwaysUpToDate, SQLServer2022."
  }
}

variable "pricing_model" {
  type        = string
  default     = null
  description = "`Regular` or `Freemium`. Null leaves it unmanaged. Freemium is only offered on a limited set of SKUs."

  validation {
    condition     = var.pricing_model == null || contains(["Regular", "Freemium"], var.pricing_model)
    error_message = "pricing_model must be one of: Regular, Freemium."
  }
}

variable "storage_iops" {
  type        = number
  default     = null
  description = <<-EOT
    Provisioned IOPS. Only valid while `general_purpose_v2_enabled` is true; ARM
    rejects it otherwise.

    Null is not "zero" - it means the instance keeps the IOPS included free with
    its storage allocation (3 per GB), which is usually what is wanted.
  EOT
}

variable "storage_throughput_mbps" {
  type        = number
  default     = null
  description = "Provisioned storage throughput in MB/s. Only valid while `general_purpose_v2_enabled` is true. Null keeps the included allowance."
}

variable "memory_size_in_gb" {
  type        = number
  default     = null
  description = "Flexible memory allocation in GB. Only offered on premium-series hardware (`*_G8IH` / `*_G8IM`); null takes the memory that comes with the vCore count."
}

variable "authentication_metadata" {
  type        = string
  default     = null
  description = <<-EOT
    Where the instance looks up logins and group membership: `AzureAD`, `Paired`
    or `Windows`. Null leaves it unmanaged on the Azure default.

    This is a lookup path, not an authentication toggle - it is independent of
    `entra_only_authentication_enabled`.
  EOT

  validation {
    condition     = var.authentication_metadata == null || contains(["AzureAD", "Paired", "Windows"], var.authentication_metadata)
    error_message = "authentication_metadata must be one of: AzureAD, Paired, Windows."
  }
}

variable "hybrid_secondary_usage" {
  type        = string
  default     = null
  description = <<-EOT
    Whether a hybrid-benefit secondary is billed as `Active` (readable, fully
    charged) or `Passive` (disaster recovery only, discounted). Null leaves it
    unmanaged.

    Declaring `Passive` on an instance that is actually serving reads is a
    licensing misstatement, not a discount.
  EOT

  validation {
    condition     = var.hybrid_secondary_usage == null || contains(["Active", "Passive"], var.hybrid_secondary_usage)
    error_message = "hybrid_secondary_usage must be one of: Active, Passive."
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
    will not change it afterwards - a new value replaces the instance.

    ⚠️ ON A MANAGED INSTANCE THIS IS EFFECTIVELY PERMANENT. ARM requires a SQL
    login at creation, and enabling `entra_only_authentication_enabled`
    afterwards blocks resetting its password - so the credential that creates
    the instance is the credential it keeps. It is inert while Entra-only stays
    on, and live again the moment it is turned off.
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
    leaves the old password on the instance with a clean plan. Ignored when
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
    Microsoft Entra administrator for the instance.

    - `login`: display label only. Azure does not resolve it, so a stale value is
      cosmetic rather than an authentication failure.
    - `object_id`: object ID of the user or group that actually gets admin.
    - `tenant_id`: defaults to the provider's tenant.

    Set as a child resource rather than inline on the instance, because ARM
    accepts the inline `administrators` property at create time only.
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

    Requires `entra_administrator` - ARM rejects enabling this on an instance with
    no Entra admin, and the module orders the two accordingly. Enabling it does
    not delete existing SQL logins; it only stops them connecting, and it blocks
    resetting the SQL admin password for as long as it is on.
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
    Managed identity configuration for the instance.

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
    Resource ID of the user-assigned identity the instance uses by default, and
    the one TDE resolves the customer-managed key through.

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
      optional `/<version>` suffix. The instance key's ARM name is derived from it.
    - `auto_rotation_enabled`: when true the instance polls the vault and moves the
      protector to a new key version within 24 hours. Turning it off pins the
      protector to the version named in the URI.

    PASS A VERSIONED URI. ARM accepts a versionless identifier but NORMALISES it
    rather than storing it, so a versionless config never matches the response and
    diffs forever. Rotation is handled by `auto_rotation_enabled` instead: Azure
    moves the protector to the newest version on its own. Keep the caller's
    key-version source refreshed alongside, or the declared version lags the one
    Azure is actually using.

    The identity in `primary_user_assigned_identity_resource_id` must already hold
    wrap/unwrap on the key before the first apply - this module does not create
    that grant, and ARM fails with `AzureKeyVaultNoServerIdentity` without it.

    SETTING THIS BACK TO NULL ON A LIVE INSTANCE IS AN UNTESTED PATH. `keyId`
    becomes null, and `ignore_null_property` drops nulls from the request -
    which on every other property was measured to mean "leave alone" rather than
    "clear", so TDE most likely stays on the customer key while Terraform stops
    tracking it. Whichever it does, it is not an outcome to reach by accident:
    move the protector deliberately rather than by deleting a line.
  EOT

  validation {
    # The instance key name is built by indexing segments of this URI, so the
    # shape is enforced here rather than left to fail on an ARM error that names
    # neither the key nor the reason.
    condition     = var.customer_managed_key == null || can(regex("^https://[^/.]+\\.[^/]+/keys/[^/]+(/[^/]+)?$", try(var.customer_managed_key.key_vault_key_uri, "")))
    error_message = "customer_managed_key.key_vault_key_uri must look like https://<vault>.vault.azure.net/keys/<key> with an optional /<version> suffix."
  }
}

# -----------------------------------------------------------------------------
# Optional - threat protection
# -----------------------------------------------------------------------------

variable "advanced_threat_protection_enabled" {
  type        = bool
  default     = null
  description = <<-EOT
    Whether Microsoft Defender for SQL threat detection is on for this instance.
    Null leaves it unmanaged.

    ⚠️ THIS AND `security_alert_policy.enabled` ARE THE SAME SWITCH seen through
    two ARM resources - `advancedThreatProtectionSettings` is the newer surface,
    `securityAlertPolicies` the older one that also carries the notification
    settings. Setting them to opposite values gives an apply that flips the state
    twice and lands on whichever resource Terraform happened to write last.
  EOT
}

variable "security_alert_policy" {
  type = object({
    enabled              = optional(bool, true)
    disabled_alerts      = optional(list(string), null)
    email_account_admins = optional(bool, null)
    email_addresses      = optional(list(string), null)
    retention_in_days    = optional(number, null)
    storage_endpoint     = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Threat-detection alert policy. Null leaves it unmanaged.

    - `enabled`: maps to ARM `state`. See the warning on
      `advanced_threat_protection_enabled` - these two toggle the same feature.
    - `disabled_alerts`: alert types to suppress, e.g. `Sql_Injection`,
      `Data_Exfiltration`. A LIST, not a set: ARM returns the array in its own
      order and a set would be re-sorted into a different one and diff forever.
    - `email_addresses` / `email_account_admins`: who gets notified.
    - `storage_endpoint` / `retention_in_days`: only for blob-storage audit of
      the alerts themselves.

    Each optional field is OMITTED from the request when null rather than sent as
    a null. ARM materialises the unset ones as `[""]`, `""` and `0`, and a
    configured null would diff against that on every plan; an omitted property is
    not compared at all.
  EOT
}

variable "vulnerability_assessment" {
  type = object({
    recurring_scans_enabled   = optional(bool, true)
    email_subscription_admins = optional(bool, true)
    emails                    = optional(list(string), null)
    storage_container_path    = optional(string, null)
  })
  default     = null
  description = <<-EOT
    SQL vulnerability assessment. Null leaves it unmanaged.

    - `recurring_scans_enabled`: run the weekly scan.
    - `email_subscription_admins` / `emails`: who receives the scan summary.
    - `storage_container_path`: `https://<account>.blob.core.windows.net/<container>/`
      for the classic configuration, which stores results and baselines in your
      own storage. Leave null to use the express configuration, where Defender
      for SQL keeps them.

    Requires Microsoft Defender for SQL to be enabled on the subscription or the
    instance; ARM accepts the resource regardless and the scans simply never run.
  EOT
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
    Role assignments scoped to the managed instance, keyed by stable name.

    These are CONTROL-plane grants. Nothing here gives access to data inside the
    instance - that comes from the Entra administrator and the logins created
    within SQL itself.

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
    Diagnostic settings on the INSTANCE, keyed by stable name.

    Instance scope carries `ResourceUsageStats` and `SQLSecurityAuditEvents`;
    per-database telemetry (`QueryStoreRuntimeStatistics`, `Errors`, and the
    rest) is a category of each managed DATABASE and needs its own setting there.

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
    - `name`: optional. Defaults to `lock-<instance-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

# -----------------------------------------------------------------------------
# Optional - operations
# -----------------------------------------------------------------------------

variable "timeouts" {
  type = object({
    create = optional(string, "8h")
    read   = optional(string, "10m")
    update = optional(string, "8h")
    delete = optional(string, "8h")
  })
  default     = {}
  description = <<-EOT
    Operation timeouts for the instance itself. The children are fast and use the
    provider defaults.

    ⚠️ THE DEFAULTS HERE ARE DELIBERATELY ENORMOUS. Creating a managed instance
    means standing up a virtual cluster, and Azure documents it as taking up to
    six hours - the first instance in a subnet is the slow one. AzAPI's own
    30-minute default would abandon every create mid-flight, leaving a
    half-provisioned instance that Terraform no longer tracks.

    Deletes are equally slow, and the last instance out of a virtual cluster
    waits on the cluster teardown behind it.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional - metadata
# -----------------------------------------------------------------------------

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the managed instance."
}
