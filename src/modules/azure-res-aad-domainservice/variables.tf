# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "domain_name" {
  type        = string
  description = <<-EOT
    DNS name of the managed domain, e.g. `aaddscontoso.com`. Cannot be changed after
    create.

    The first label becomes the domain's NetBIOS name — Entra Domain Services offers
    no way to set it separately — so it is limited to 15 characters.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$", var.domain_name)) && length(var.domain_name) <= 255
    error_message = "domain_name must be a DNS name: dot-separated labels of letters, digits and hyphens, each 1-63 characters, not starting or ending with a hyphen."
  }

  validation {
    condition     = length(split(".", var.domain_name)[0]) <= 15
    error_message = "The first label of domain_name becomes the NetBIOS name and must be 15 characters or fewer."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the managed domain in. Resolved against the provider's subscription. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region of the managed domain and its initial replica set. Must be the region of the virtual network that holds `subnet_resource_id`."
  nullable    = false

  validation {
    condition     = length(var.location) > 0
    error_message = "location must not be empty."
  }
}

variable "subnet_resource_id" {
  type        = string
  description = <<-EOT
    Resource ID of the subnet for the initial replica set. Cannot be changed after
    create — Entra Domain Services cannot move to another virtual network once
    enabled.

    The subnet must be dedicated to the managed domain, and must not be
    `GatewaySubnet`.
  EOT
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be a subnet resource ID."
  }

  validation {
    condition     = !can(regex("(?i)/subnets/GatewaySubnet$", var.subnet_resource_id))
    error_message = "subnet_resource_id must not be GatewaySubnet — Entra Domain Services is not supported there."
  }
}

variable "sku" {
  type        = string
  description = "SKU of the managed domain: `Standard`, `Enterprise` or `Premium`. Changes in place, in either direction. Additional replica sets need `Enterprise` or `Premium`."
  nullable    = false

  # The values the Bicep AVM module allows. The REST specification models `sku`
  # as an open string, so without this a typo reaches ARM.
  validation {
    condition     = contains(["Standard", "Enterprise", "Premium"], var.sku)
    error_message = "sku must be one of: Standard, Enterprise, Premium."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  default     = null
  description = "Name of the `Microsoft.AAD/domainServices` resource. Defaults to `domain_name`, which is what the portal uses."

  validation {
    condition = var.name == null || (
      length(coalesce(var.name, "x")) >= 3 && length(coalesce(var.name, "x")) <= 255 &&
      can(regex("^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$", coalesce(var.name, "x")))
    )
    error_message = "name must be 3-255 characters of dot-separated labels of letters, digits and hyphens, each 1-63 characters, not starting or ending with a hyphen."
  }
}

variable "replica_sets" {
  type = list(object({
    location           = string
    subnet_resource_id = string
  }))
  default     = []
  description = <<-EOT
    Additional replica sets, each in its own region. The initial replica set is
    built from `location` and `subnet_resource_id` and is not listed here.

    Append new entries to the end and remove from the end. Replica set entries
    carry no name, so azapi compares the sent and returned lists by position —
    inserting or reordering diffs every entry after the change.

    Needs the `Enterprise` or `Premium` SKU.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for replica_set in var.replica_sets :
      can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", replica_set.subnet_resource_id))
    ])
    error_message = "Each replica_sets subnet_resource_id must be a subnet resource ID."
  }

  validation {
    condition = length(distinct(concat(
      [lower(replace(var.location, " ", ""))],
      [for replica_set in var.replica_sets : lower(replace(replica_set.location, " ", ""))],
    ))) == length(var.replica_sets) + 1
    error_message = "Each replica set needs its own region: no two replica_sets may share a location, and none may use the managed domain's own location."
  }

  validation {
    condition     = length(var.replica_sets) == 0 || contains(["Enterprise", "Premium"], var.sku)
    error_message = "Additional replica sets need the Enterprise or Premium SKU."
  }
}

variable "domain_configuration_type" {
  type        = string
  default     = "FullySynced"
  description = "`FullySynced` (a user forest) or `ResourceTrusting` (a resource forest). Cannot be changed after create. Forest trusts themselves are not managed by this module."
  nullable    = false

  validation {
    condition     = contains(["FullySynced", "ResourceTrusting"], var.domain_configuration_type)
    error_message = "domain_configuration_type must be one of: FullySynced, ResourceTrusting."
  }
}

variable "filtered_sync_enabled" {
  type        = bool
  default     = false
  description = <<-EOT
    Synchronise only the groups in the managed domain's sync scope, and their
    members, rather than the whole directory. The scope itself is not set here.

    Defaults to `false`, the service's own default and the azurerm provider's. The
    Bicep AVM module defaults it on.
  EOT
  nullable    = false
}

variable "sync_scope" {
  type        = string
  default     = "All"
  description = "Which users synchronise: `All`, or `CloudOnly` to leave out users synchronised from on-premises."
  nullable    = false

  validation {
    condition     = contains(["All", "CloudOnly"], var.sync_scope)
    error_message = "sync_scope must be one of: All, CloudOnly."
  }
}

variable "security" {
  type = object({
    ntlm_v1_enabled                 = optional(bool, false)
    kerberos_rc4_encryption_enabled = optional(bool, false)
    kerberos_armoring_enabled       = optional(bool, true)
    ldap_signing_enabled            = optional(bool, false)
    channel_binding_enabled         = optional(bool, false)
    sync_ntlm_passwords             = optional(bool, true)
    sync_kerberos_passwords         = optional(bool, true)
    sync_on_prem_passwords          = optional(bool, true)
    sync_on_prem_sam_account_name   = optional(bool, false)
  })
  default     = {}
  description = <<-EOT
    Domain security settings. Every one is sent on every write — the service's own
    defaults allow NTLMv1 and RC4, and a write that leaves a setting out resets it.

    - `ntlm_v1_enabled`: accept NTLMv1. Off by default.
    - `kerberos_rc4_encryption_enabled`: issue RC4-HMAC Kerberos tickets. Off by
      default. Turning it off on a live domain breaks anything still negotiating
      RC4: older appliances, and service accounts whose
      `msDS-SupportedEncryptionTypes` is unset or RC4-only.
    - `kerberos_armoring_enabled`: Kerberos armoring (FAST). On by default, as in
      the Bicep AVM module.
    - `ldap_signing_enabled`: require signed LDAP binds. Off by default, the
      service's default — on, it rejects unsigned simple binds over port 389.
    - `channel_binding_enabled`: require LDAP channel binding over LDAPS. Off by
      default, the service's default.
    - `sync_ntlm_passwords`: keep NTLM password hashes in the managed domain. Off
      breaks NTLM authentication and LDAP simple binds.
    - `sync_kerberos_passwords`: keep Kerberos password hashes in the managed domain.
    - `sync_on_prem_passwords`: let users synchronised from on-premises sign in
      with their on-premises password.
    - `sync_on_prem_sam_account_name`: take `sAMAccountName` from Entra ID's
      `onPremisesSamAccountName`. Off by default, the service's default.

    TLS 1.0 and 1.1 are always disabled; the service no longer offers them.

    Names follow the azurerm provider's `security` block where the two overlap.
  EOT
  nullable    = false
}

variable "notifications" {
  type = object({
    notify_dc_admins      = optional(bool, true)
    notify_global_admins  = optional(bool, true)
    additional_recipients = optional(list(string), [])
  })
  default     = {}
  description = <<-EOT
    Who is emailed when the managed domain raises a health alert.

    - `notify_dc_admins`: members of `AAD DC Administrators`.
    - `notify_global_admins`: the tenant's Global Administrators.
    - `additional_recipients`: further email addresses.

    Names follow the azurerm provider's `notifications` block.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for recipient in var.notifications.additional_recipients :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", recipient))
    ])
    error_message = "Each notifications.additional_recipients entry must be an email address."
  }
}

variable "secure_ldap" {
  type = object({
    external_access_enabled = optional(bool, false)
  })
  default     = null
  description = <<-EOT
    Secure LDAP (LDAPS). Null disables it — explicitly, on every write, so LDAPS
    enabled outside Terraform is turned off by the next apply.

    - `external_access_enabled`: publish LDAPS on the managed domain's public IP
      address. Restrict TCP 636 on the domain's network security group before
      turning it on.

    Setting this requires `secure_ldap_certificate`.
  EOT
}

variable "secure_ldap_certificate" {
  type = object({
    pfx_certificate          = string
    pfx_certificate_password = string
  })
  default     = null
  sensitive   = true
  description = <<-EOT
    The secure LDAP certificate. Required when `secure_ldap` is set, and rejected
    when it is not.

    - `pfx_certificate`: the PFX file, base64-encoded, including the private key.
      Its subject or a subject alternative name must cover the domain
      (`*.<domain_name>`).
    - `pfx_certificate_password`: the password protecting the PFX.

    Sent on every write and stored in state, as the azurerm provider does — see the
    banner in `main.tf` for why AzAPI's `sensitive_body` is not used. Changing
    either value uploads the new certificate.
  EOT

  validation {
    condition     = nonsensitive((var.secure_ldap == null) == (var.secure_ldap_certificate == null))
    error_message = "secure_ldap_certificate must be set exactly when secure_ldap is set."
  }
}

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
    Diagnostic settings on the managed domain, keyed by stable name.

    The managed domain's log categories are the security audit events
    (`AccountLogon`, `AccountManagement`, `DetailTracking`,
    `DirectoryServiceAccess`, `LogonLogoff`, `ObjectAccess`, `PolicyChange`,
    `PrivilegeUse`, `SystemSecurity`) and the DNS server audits
    (`DNSServerAuditsDynamicUpdates`, `DNSServerAuditsGeneral`). Its metrics
    category is `AllMetrics`.

    At least one destination must be set per entry.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for setting in values(var.diagnostic_settings) :
      setting.workspace_resource_id != null || setting.storage_account_resource_id != null ||
      setting.event_hub_authorization_rule_resource_id != null || setting.marketplace_partner_resource_id != null
    ])
    error_message = "Each diagnostic_settings entry needs a destination: workspace_resource_id, storage_account_resource_id, event_hub_authorization_rule_resource_id or marketplace_partner_resource_id."
  }
}

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
    Map of managed-domain-scope role assignments, keyed by a stable identifier.

    `role_definition_id_or_name` accepts either:
    - a full role definition resource ID (`/subscriptions/.../providers/Microsoft.Authorization/roleDefinitions/<uuid>`), or
    - a built-in role name (e.g., `Reader`), resolved by a subscription-scope lookup.

    `name` is the assignment's ARM name (a GUID). Leave it unset — a random UUID is generated — unless you
    are adopting an assignment that already exists, where the existing GUID must be supplied to avoid a
    destroy-and-recreate.

    Set `principal_type = "ServicePrincipal"` when the principal is a service principal or a managed
    identity, so ARM skips the directory lookup that fails on a principal created moments earlier.

    Do not edit `principal_id` or `role_definition_id_or_name` on an existing key — ARM rejects the update.
    Add a new key and remove the old one instead.

    These are Azure control-plane roles on the resource. They grant nothing inside the managed domain;
    administration there is membership of the `AAD DC Administrators` group.

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

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Resource lock configuration.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<resource-name>`.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

variable "timeouts" {
  type = object({
    create = optional(string, "3h")
    read   = optional(string, "5m")
    update = optional(string, "2h")
    delete = optional(string, "1h")
  })
  default     = {}
  description = <<-EOT
    Operation timeouts for the managed domain itself. The children are fast and use
    the provider defaults.

    AzAPI's own 30-minute default is too short for a managed domain: deletes and
    replica set changes are long-running. The defaults here are the ones the
    azurerm provider uses for this resource.
  EOT
  nullable    = false
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the managed domain."
}
