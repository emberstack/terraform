# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the managed cluster."
  nullable    = false

  # ARM's pattern is `^[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9]$`, checked
  # against ResourceNameParameter in the containerservice 2025-09-02-preview
  # swagger. RE2 has no lookahead, so the pattern carries the length bound by
  # itself and a single-character name is rejected by ARM too.
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]{0,61}[a-zA-Z0-9]$", var.name))
    error_message = "name must be 2-63 characters, start and end with a letter or digit, and otherwise contain only letters, digits, underscores and hyphens."
  }
}

variable "location" {
  type        = string
  description = "Azure region where the cluster should be deployed."
  nullable    = false
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group where the cluster will be created. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "default_node_pool" {
  type = object({
    name                    = string
    vm_size                 = string
    vnet_subnet_resource_id = optional(string, null)
    pod_subnet_resource_id  = optional(string, null)
    os_sku                  = optional(string, "Ubuntu")
    os_disk_size_gb         = optional(number, null)
    os_disk_type            = optional(string, "Ephemeral")
    kubelet_disk_type       = optional(string, null)
    max_pods                = optional(number, null)
    host_encryption_enabled = optional(bool, true)
    fips_enabled            = optional(bool, false)
    node_public_ip_enabled  = optional(bool, false)
    zones                   = optional(list(string), ["1", "2", "3"])
    scale_down_mode         = optional(string, null)
    node_labels             = optional(map(string), {})
    node_taints             = optional(list(string), [])
    auto_scaling = optional(object({
      enabled   = optional(bool, true)
      min_count = optional(number, 3)
      max_count = optional(number, 6)
    }), {})
    node_count = optional(number, 3)
    upgrade_settings = optional(object({
      max_surge                     = optional(string, "10%")
      drain_timeout_in_minutes      = optional(number, null)
      node_soak_duration_in_minutes = optional(number, null)
    }), {})
    tags = optional(map(string), {})
  })
  description = <<-EOT
    The cluster's system node pool, written into the create body.

    **Every field here is create-only, and a later change is silently dropped.**
    The cluster ignores drift on `agentPoolProfiles` entirely — it has to, or a
    PUT carrying only this pool would strip the ones the `agentpool` submodule
    owns — so editing `vm_size` or `zones` after the cluster exists produces a
    clean plan and no change at all. Resizing the system pool means adding a
    second System pool through the submodule, moving workloads across, and
    retiring this one.

    ARM will not create a managed cluster with an empty `agentPoolProfiles`, so
    this pool is not optional and its `mode` is always `System`. Every other pool
    belongs in the `agentpool` submodule, which owns pools as independent ARM
    child resources — see the note on `agentPoolProfiles` in `main.tf`.

    `node_count` applies only when `auto_scaling.enabled = false`; with the
    autoscaler on, the initial size is `auto_scaling.min_count` and the running
    count is the autoscaler's from then on.

    Leave `os_disk_size_gb` null to take the OS SKU's default. On a VM size with
    no cache or temp disk, `os_disk_type = "Ephemeral"` is rejected by ARM — set
    `"Managed"` there.
  EOT
  nullable    = false

  # 1-12 for Linux, and the map key seeds the NetBIOS hostname on Windows, which
  # is where the 6-character ceiling comes from. The system pool is Linux-only,
  # so only the Linux bound applies here.
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{0,11}$", var.default_node_pool.name))
    error_message = "default_node_pool.name must be 1-12 characters, start with a lowercase letter, and contain only lowercase letters and digits."
  }

  validation {
    condition     = contains(["Ephemeral", "Managed"], var.default_node_pool.os_disk_type)
    error_message = "default_node_pool.os_disk_type must be one of: Ephemeral, Managed."
  }

  validation {
    condition = (
      !var.default_node_pool.auto_scaling.enabled ||
      var.default_node_pool.auto_scaling.min_count <= var.default_node_pool.auto_scaling.max_count
    )
    error_message = "default_node_pool.auto_scaling.min_count must not exceed max_count."
  }
}

# -----------------------------------------------------------------------------
# Cluster
# -----------------------------------------------------------------------------

variable "dns_prefix" {
  type        = string
  default     = null
  description = <<-EOT
    DNS prefix for the cluster's API server FQDN. Defaults to `name`.

    Create-only: ARM rejects a change on an existing cluster. The charset is
    narrower than a cluster name's — no underscores — so a `name` containing one
    has to set this explicitly.
  EOT

  # Checks the value that is actually sent, not the input. Skipping the check on
  # null would let a `name` containing an underscore — which `name` allows and a
  # DNS prefix does not — through a clean plan and into an ARM rejection.
  validation {
    condition     = can(regex("^[a-zA-Z0-9][a-zA-Z0-9-]{0,52}[a-zA-Z0-9]$", coalesce(var.dns_prefix, var.name)))
    error_message = "dns_prefix must be 2-54 characters, start and end with a letter or digit, and otherwise contain only letters, digits and hyphens. It defaults to `name`, so set it explicitly when `name` contains an underscore."
  }
}

variable "kubernetes_version" {
  type        = string
  default     = null
  description = <<-EOT
    Kubernetes version, as `<major>.<minor>` to track the latest patch, or a full
    `<major>.<minor>.<patch>` to pin one. Null leaves the version to Azure.

    Written by a separate ARM call rather than the create body, because the
    cluster resource ignores drift on `kubernetesVersion` — see `main.tf`.

    A full three-part pin only works with an upgrade channel that cannot move
    the version. `stable`, `rapid` and `patch` all can: once Azure has upgraded
    the cluster past the pin, that separate call tries to write the old version
    back, AKS rejects the downgrade, and every apply fails from then on. Use
    `<major>.<minor>` with a live channel and let Azure carry the patch.
  EOT

  validation {
    condition     = var.kubernetes_version == null || can(regex("^[0-9]+\\.[0-9]+(\\.[0-9]+)?$", var.kubernetes_version))
    error_message = "kubernetes_version must look like \"1.33\" or \"1.33.2\"."
  }

  validation {
    condition = (
      var.kubernetes_version == null ||
      !can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.kubernetes_version)) ||
      contains(["none", "node-image"], var.auto_upgrade_profile.upgrade_channel)
    )
    error_message = "A three-part kubernetes_version pin requires auto_upgrade_profile.upgrade_channel to be \"none\" or \"node-image\" — any other channel moves the version and the next apply fails trying to downgrade it. Pin \"<major>.<minor>\" instead to track patches."
  }
}

variable "sku" {
  type = object({
    name = optional(string, "Base")
    tier = optional(string, "Standard")
  })
  default     = {}
  description = <<-EOT
    Control plane SKU.

    `tier` defaults to `Standard`, not Azure's `Free`: the Free tier carries no
    uptime SLA and caps the cluster well below what a production workload needs.
    `Premium` additionally requires `support_plan = "AKSLongTermSupport"`.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Base", "Automatic"], var.sku.name)
    error_message = "sku.name must be one of: Base, Automatic."
  }

  validation {
    condition     = contains(["Free", "Standard", "Premium"], var.sku.tier)
    error_message = "sku.tier must be one of: Free, Standard, Premium."
  }
}

variable "support_plan" {
  type        = string
  default     = "KubernetesOfficial"
  description = "Support plan for the cluster. `AKSLongTermSupport` extends support past community EOL and requires `sku.tier = \"Premium\"`."
  nullable    = false

  validation {
    condition     = contains(["KubernetesOfficial", "AKSLongTermSupport"], var.support_plan)
    error_message = "support_plan must be one of: KubernetesOfficial, AKSLongTermSupport."
  }

  validation {
    condition     = var.support_plan != "AKSLongTermSupport" || var.sku.tier == "Premium"
    error_message = "support_plan = \"AKSLongTermSupport\" requires sku.tier = \"Premium\"."
  }
}

variable "node_resource_group" {
  type        = string
  default     = null
  description = "Name of the resource group holding the cluster's own infrastructure (the `MC_*` group). Create-only — a change replaces the cluster."
}

variable "auto_upgrade_profile" {
  type = object({
    upgrade_channel         = optional(string, "stable")
    node_os_upgrade_channel = optional(string, "NodeImage")
  })
  default     = {}
  description = <<-EOT
    Automatic upgrade channels.

    `upgrade_channel` moves the control plane and pools between Kubernetes
    versions; `node_os_upgrade_channel` handles node OS images only. An upgrade
    channel other than `none` moves `kubernetesVersion` out from under Terraform,
    which is why the cluster ignores drift on it.
  EOT
  nullable    = false

  validation {
    condition     = contains(["none", "patch", "rapid", "stable", "node-image"], var.auto_upgrade_profile.upgrade_channel)
    error_message = "auto_upgrade_profile.upgrade_channel must be one of: none, patch, rapid, stable, node-image."
  }

  validation {
    condition     = contains(["None", "Unmanaged", "NodeImage", "SecurityPatch"], var.auto_upgrade_profile.node_os_upgrade_channel)
    error_message = "auto_upgrade_profile.node_os_upgrade_channel must be one of: None, Unmanaged, NodeImage, SecurityPatch."
  }
}

variable "upgrade_override" {
  type = object({
    force_upgrade = bool
    until         = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Override the blockers an upgrade normally respects — pod disruption budgets
    and deprecated-API usage.

    `until` is an RFC 3339 timestamp after which the override lapses; ARM caps it
    at 30 days out and assigns its own when the property is omitted. Leaving it
    null is the quieter option — AzAPI compares only the properties the body
    declares, so a server-assigned value nothing asked for never shows as drift.
  EOT
}

variable "node_provisioning_profile" {
  type = object({
    mode = optional(string, "Manual")
  })
  default     = {}
  description = <<-EOT
    Node provisioning mode. `Manual` means pools exist only because this module
    and the `agentpool` submodule declare them.

    `Auto` hands pool sizing and shape to the node auto-provisioning (Karpenter)
    controller, which will fight any pool Terraform manages.
  EOT
  nullable    = false

  validation {
    condition     = contains(["Manual", "Auto"], var.node_provisioning_profile.mode)
    error_message = "node_provisioning_profile.mode must be one of: Manual, Auto."
  }
}

variable "cost_analysis_enabled" {
  type        = bool
  default     = false
  description = "Surface Kubernetes namespace and asset cost breakdowns in Microsoft Cost Management. Requires `sku.tier` of `Standard` or `Premium`."
  nullable    = false

  validation {
    condition     = !var.cost_analysis_enabled || contains(["Standard", "Premium"], var.sku.tier)
    error_message = "cost_analysis_enabled requires sku.tier to be Standard or Premium."
  }
}

# -----------------------------------------------------------------------------
# Networking
# -----------------------------------------------------------------------------

variable "network_profile" {
  type = object({
    network_plugin      = optional(string, "azure")
    network_plugin_mode = optional(string, null)
    network_policy      = optional(string, null)
    network_dataplane   = optional(string, null)
    outbound_type       = optional(string, "loadBalancer")
    load_balancer_sku   = optional(string, "standard")
    pod_cidr            = optional(string, null)
    service_cidr        = optional(string, null)
    dns_service_ip      = optional(string, null)
  })
  default     = {}
  description = <<-EOT
    Cluster network profile.

    `outbound_type` defaults to Azure's own `loadBalancer`. `userDefinedRouting`
    is the right answer behind a firewall, but it requires a 0.0.0.0/0 route to
    already exist on the node subnet — set it deliberately rather than inheriting
    it.

    `network_plugin_mode` defaults to null, which is node-subnet Azure CNI —
    every pod takes an address from the node's subnet. `overlay` moves pods onto
    their own address space and then requires `pod_cidr`, which must not overlap
    the VNet. The default is null rather than `overlay` so that the variable's
    own default is a valid configuration; a caller wanting overlay opts into
    both fields together.

    `service_cidr` and `dns_service_ip` may be left null to take Azure's
    defaults; when either is set, so must the other be, and `dns_service_ip` has
    to fall inside `service_cidr`.
  EOT
  nullable    = false

  validation {
    condition     = contains(["azure", "kubenet", "none"], var.network_profile.network_plugin)
    error_message = "network_profile.network_plugin must be one of: azure, kubenet, none."
  }

  validation {
    condition     = var.network_profile.network_plugin_mode == null || var.network_profile.network_plugin_mode == "overlay"
    error_message = "network_profile.network_plugin_mode must be \"overlay\" or null."
  }

  validation {
    condition     = contains(["loadBalancer", "userDefinedRouting", "managedNATGateway", "userAssignedNATGateway", "none"], var.network_profile.outbound_type)
    error_message = "network_profile.outbound_type must be one of: loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway, none."
  }

  validation {
    condition     = var.network_profile.network_plugin_mode != "overlay" || var.network_profile.pod_cidr != null
    error_message = "network_profile.pod_cidr is required when network_plugin_mode is \"overlay\"."
  }

  validation {
    condition     = (var.network_profile.service_cidr == null) == (var.network_profile.dns_service_ip == null)
    error_message = "network_profile.service_cidr and dns_service_ip must be set together, or both left null."
  }

  # `can()` has to wrap the whole call. `cidrhost` and `cidrnetmask` raise on a
  # malformed string rather than returning null, so an unguarded call aborts the
  # validation with the function's own error and never reaches error_message.
  validation {
    condition     = var.network_profile.service_cidr == null || can(cidrnetmask(var.network_profile.service_cidr))
    error_message = "network_profile.service_cidr must be a valid CIDR block."
  }

  validation {
    condition     = var.network_profile.pod_cidr == null || can(cidrnetmask(var.network_profile.pod_cidr))
    error_message = "network_profile.pod_cidr must be a valid CIDR block."
  }
}

variable "api_server_access_profile" {
  type = object({
    private_cluster_enabled             = optional(bool, true)
    private_cluster_public_fqdn_enabled = optional(bool, false)
    private_dns_zone                    = optional(string, "system")
    authorized_ip_ranges                = optional(set(string), [])
    run_command_enabled                 = optional(bool, true)
  })
  default     = {}
  description = <<-EOT
    API server reachability.

    `private_dns_zone` takes `system` (AKS creates and owns the zone), `none`
    (no zone; resolution is the caller's problem), or the resource ID of a zone
    you own. A bring-your-own zone additionally needs the cluster's user-assigned
    identity to hold Private DNS Zone Contributor on the zone and Network
    Contributor on the VNet **before** the cluster is created — this module does
    not grant them, because both scopes belong to resources it does not own.

    `authorized_ip_ranges` is ignored on a private cluster.
  EOT
  nullable    = false

  validation {
    condition = (
      contains(["system", "none"], lower(var.api_server_access_profile.private_dns_zone)) ||
      startswith(var.api_server_access_profile.private_dns_zone, "/")
    )
    error_message = "api_server_access_profile.private_dns_zone must be \"system\", \"none\", or a private DNS zone resource ID."
  }

  validation {
    condition = (
      var.api_server_access_profile.private_cluster_enabled ||
      lower(var.api_server_access_profile.private_dns_zone) == "system"
    )
    error_message = "api_server_access_profile.private_dns_zone applies only to a private cluster; leave it at \"system\" when private_cluster_enabled is false."
  }
}

variable "public_network_access" {
  type        = string
  default     = null
  description = <<-EOT
    Allow or deny public network access to the cluster — `Enabled` or
    `Disabled`. Null leaves the property unset and takes Azure's default.

    This is not an alternative spelling of
    `api_server_access_profile.private_cluster_enabled`, and the two are not
    interchangeable. A private cluster puts the API server behind a private
    endpoint in your virtual network, and that is decided at creation and never
    afterwards. This property only gates the public path, and it is mutable — so
    on a public cluster it is the way to withdraw public reachability later
    without rebuilding.

    On a private cluster it is redundant: there is no public endpoint to close.
    Leave it null there.
  EOT

  validation {
    condition     = var.public_network_access == null || contains(["Enabled", "Disabled"], coalesce(var.public_network_access, "Enabled"))
    error_message = "public_network_access must be \"Enabled\" or \"Disabled\"."
  }
}

# -----------------------------------------------------------------------------
# Identity and access
# -----------------------------------------------------------------------------

variable "managed_identities" {
  type = object({
    system_assigned            = optional(bool, false)
    user_assigned_resource_ids = optional(set(string), [])
  })
  default     = { system_assigned = true }
  description = <<-EOT
    Control plane identity. Exactly one of the two must be configured — AKS does
    not accept both on the same cluster.

    A user-assigned identity is the only workable choice when the cluster needs
    rights on something that must be granted *before* it exists — a bring-your-own
    private DNS zone, or a KMS key. A system-assigned principal does not exist
    until the create call returns, so those grants cannot be in place in time.
  EOT
  nullable    = false

  validation {
    condition = (
      var.managed_identities.system_assigned != (length(var.managed_identities.user_assigned_resource_ids) > 0)
    )
    error_message = "Set exactly one of managed_identities.system_assigned or managed_identities.user_assigned_resource_ids — AKS rejects a cluster carrying both."
  }

  validation {
    condition     = length(var.managed_identities.user_assigned_resource_ids) <= 1
    error_message = "AKS accepts at most one user-assigned identity on the control plane."
  }
}

variable "kubelet_identity" {
  type = object({
    client_id                 = string
    object_id                 = string
    user_assigned_resource_id = string
  })
  default     = null
  description = <<-EOT
    Bring-your-own kubelet identity — the identity the nodes use to pull images
    and reach other Azure services. Null lets AKS create and manage one.

    Create-only in practice: changing it on an existing cluster is a manual,
    disruptive operation Azure documents separately, so a change here is not
    something the module can reconcile for you.
  EOT
}

variable "rbac_enabled" {
  type        = bool
  default     = true
  description = "Enable Kubernetes RBAC. Create-only, and disabling it rules out Entra integration entirely."
  nullable    = false
}

variable "aad_profile" {
  type = object({
    azure_rbac_enabled     = optional(bool, true)
    admin_group_object_ids = optional(set(string), [])
    tenant_id              = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Entra ID integration, in its managed form. Null disables it.

    With `azure_rbac_enabled`, Kubernetes authorization is driven by Azure RBAC
    role assignments rather than in-cluster bindings, and `admin_group_object_ids`
    becomes a break-glass path rather than the normal one. Assign roles directly
    to a managed identity where one is involved — the authorization webhook does
    not reliably resolve a managed identity's transitive group membership.

    `tenant_id` defaults to the provider's tenant.
  EOT
}

variable "local_accounts_disabled" {
  type        = bool
  default     = true
  description = "Disable the cluster's static local admin account, leaving Entra as the only way in. Azure's own default is `false`; this module hardens it, because a local account is a credential nobody rotates."
  nullable    = false
}

variable "oidc_issuer_enabled" {
  type        = bool
  default     = true
  description = "Publish an OIDC issuer URL. Required by workload identity, and a prerequisite for any federated credential pointing at this cluster."
  nullable    = false
}

variable "linux_profile" {
  type = object({
    admin_username = string
    ssh_public_key = string
  })
  default     = null
  description = "Linux node admin user and its authorised SSH key. Null omits the profile, leaving nodes without SSH access — which is the better default."
}

variable "windows_profile" {
  type = object({
    admin_username        = string
    admin_password        = string
    license_type          = optional(string, null)
    csi_proxy_enabled     = optional(bool, true)
    outbound_nat_enabled  = optional(bool, null)
    gmsa_enabled          = optional(bool, false)
    gmsa_dns_server       = optional(string, null)
    gmsa_root_domain_name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Windows node admin credentials. Required before any Windows pool can join;
    AKS populates a default profile when a Windows pool is added without one.

    `admin_password` is sent through AzAPI's `sensitive_body`, so it stays out of
    the plan — but it still lands in state. Supply it from an ephemeral resource
    or a write-only variable, not a literal. Bump `windows_profile_password_version`
    to roll it.

    `outbound_nat_enabled = false` is rejected outright on an overlay cluster:
    the pod CIDR is not VNet-routable, so nodes must SNAT pod traffic to the host
    IP. Leave it null there.
  EOT
}

variable "windows_profile_password_version" {
  type        = number
  default     = 1
  description = "Bump to force `windows_profile.admin_password` to be rewritten. A sensitive value is invisible to the plan, so a rotation needs an ordinary value to hang the change on."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Security
# -----------------------------------------------------------------------------

variable "disk_encryption_set_resource_id" {
  type        = string
  default     = null
  description = <<-EOT
    Disk encryption set for customer-managed keys on node OS and data disks.
    Create-only.

    The cluster identity needs Reader on the set before the CSI driver can attach
    an encrypted disk, or volume attachment fails with `LinkedAuthorizationFailed`.
    That grant is the caller's — the set is not this module's resource.
  EOT

  validation {
    condition     = var.disk_encryption_set_resource_id == null || startswith(coalesce(var.disk_encryption_set_resource_id, "/"), "/")
    error_message = "disk_encryption_set_resource_id must be a resource ID."
  }
}

variable "key_management_service" {
  type = object({
    key_vault_key_id          = string
    key_vault_resource_id     = optional(string, null)
    key_vault_network_access  = optional(string, "Public")
    infrastructure_encryption = optional(bool, false)
  })
  default     = null
  description = <<-EOT
    etcd encryption with a customer-managed key (KMS).

    Pass a **versionless** key ID so key rotation does not require a cluster
    update. `key_vault_resource_id` is mandatory when
    `key_vault_network_access = "Private"`, which additionally requires API server
    VNet integration.

    The cluster identity must already hold Key Vault Crypto User on the vault when
    this is applied. Combined with a system-assigned identity that is a deadlock —
    the principal does not exist until the cluster does — so KMS effectively
    requires `managed_identities.user_assigned_resource_ids`.

    `infrastructure_encryption` adds a second, platform-managed layer over
    Kubernetes objects. It is preview-gated: the `KMSPMKPreview` feature flag has
    to be registered on the subscription and the cluster has to be on Kubernetes
    1.33 or newer, so it defaults off.

    Both states are sent explicitly whenever this block is set, so the flag can
    be turned back off — omitting it would be dropped as a null and the change
    would never take. The consequence is that a subscription without the preview
    feature registered sees `infrastructureEncryption = "Disabled"` in the body
    rather than nothing at all.
  EOT

  validation {
    condition     = var.key_management_service == null || contains(["Public", "Private"], try(var.key_management_service.key_vault_network_access, ""))
    error_message = "key_management_service.key_vault_network_access must be one of: Public, Private."
  }

  validation {
    condition = (
      var.key_management_service == null ||
      try(var.key_management_service.key_vault_network_access, "") != "Private" ||
      try(var.key_management_service.key_vault_resource_id, null) != null
    )
    error_message = "key_management_service.key_vault_resource_id is required when key_vault_network_access is \"Private\"."
  }
}

variable "workload_identity_enabled" {
  type        = bool
  default     = true
  description = "Enable the workload identity webhook, letting a pod's service account federate to an Entra identity. Requires `oidc_issuer_enabled` — federation has nothing to trust without an issuer."
  nullable    = false

  # Both default to true, so the invalid pair is only reachable by turning one
  # of them off and forgetting the other — which ARM rejects at apply.
  validation {
    condition     = !var.workload_identity_enabled || var.oidc_issuer_enabled
    error_message = "workload_identity_enabled requires oidc_issuer_enabled — the webhook federates against the cluster's OIDC issuer."
  }
}

variable "image_cleaner" {
  type = object({
    enabled        = optional(bool, true)
    interval_hours = optional(number, 168)
  })
  default     = {}
  description = "Eraser, which removes unused and vulnerable container images from nodes. The interval is in hours and ARM accepts 24 to 2160."
  nullable    = false

  validation {
    condition     = var.image_cleaner.interval_hours >= 24 && var.image_cleaner.interval_hours <= 2160
    error_message = "image_cleaner.interval_hours must be between 24 and 2160."
  }
}

variable "microsoft_defender" {
  type = object({
    log_analytics_workspace_resource_id = string
  })
  default     = null
  description = <<-EOT
    Defender for Containers on the cluster, reporting to the named workspace.

    Leave null where Defender is turned on by a subscription-level Defender for
    Cloud plan instead — the plan writes the same property, and setting it here
    too puts the two in a loop.
  EOT
}

# -----------------------------------------------------------------------------
# Add-ons and profiles
# -----------------------------------------------------------------------------

variable "azure_policy_enabled" {
  type        = bool
  default     = true
  description = "Install the Azure Policy add-on (Gatekeeper). Without it, policy definitions in the Kubernetes category evaluate to nothing on this cluster."
  nullable    = false
}

variable "key_vault_secrets_provider" {
  type = object({
    enabled                  = optional(bool, true)
    secret_rotation_enabled  = optional(bool, true)
    secret_rotation_interval = optional(string, "2m")
  })
  default     = {}
  description = "The Key Vault secrets provider CSI driver. The add-on creates its own user-assigned identity, whose client and object IDs come back on the `key_vault_secrets_provider_identity` output."
  nullable    = false
}

variable "ingress_profile" {
  type = object({
    application_load_balancer_enabled = optional(bool, false)
    gateway_api_installation          = optional(string, null)
  })
  default     = {}
  description = <<-EOT
    Application Gateway for Containers, as the managed ALB controller add-on.

    `gateway_api_installation` takes `Standard` to have the add-on install the
    Gateway API CRDs, or `Disabled` to leave them to something else — a Helm-owned
    controller, say, which is the case whenever the CRDs are already on the
    cluster. Null leaves the property unset.

    The add-on creates its own identity in the node resource group, and that
    identity needs Network Contributor on the AGfC subnet before a gateway will
    come up. The grant is out of scope here for an ordering reason, not a tidiness
    one: the identity does not exist until this resource has been created. Its
    resource ID is on the `application_load_balancer_identity` output.
  EOT
  nullable    = false

  validation {
    condition = (
      var.ingress_profile.gateway_api_installation == null ||
      contains(["Standard", "Disabled"], coalesce(var.ingress_profile.gateway_api_installation, "Standard"))
    )
    error_message = "ingress_profile.gateway_api_installation must be one of: Standard, Disabled."
  }
}

variable "workload_autoscaler_profile" {
  type = object({
    keda_enabled                    = optional(bool, false)
    vertical_pod_autoscaler_enabled = optional(bool, false)
  })
  default     = {}
  description = "KEDA and the vertical pod autoscaler, as cluster add-ons."
  nullable    = false
}

# -----------------------------------------------------------------------------
# Interfaces
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
    Role assignments scoped to the cluster, keyed by stable name.

    `role_definition_id_or_name` accepts either a role name (e.g.
    `"Azure Kubernetes Service RBAC Reader"`) or a full role definition resource
    ID. Auto-routed by the leading `/`.

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
    Diagnostic settings on the cluster, keyed by stable name.

    `log_categories`, `log_groups` and `metric_categories` are maps of name to
    enabled, and EVERY category the resource has should appear - the disabled
    ones included. ARM materialises the full set whatever is sent, and azapi
    compares the resulting arrays wholesale, so naming only the enabled ones
    leaves the setting diffing on every plan.

    The default `log_groups = { allLogs = true }` includes `kube-audit`, which on
    a busy cluster is by far the largest table AKS emits. Enumerating
    `log_categories` instead — `kube-audit-admin` and `guard` true, the rest
    false — costs a fraction of the ingest for most of the forensic value.

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

variable "lock" {
  type = object({
    kind = string
    name = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Resource lock configuration.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<cluster-name>`.

    `ReadOnly` on a cluster blocks the control plane's own writes to the node
    resource group, which breaks scaling and upgrades. `CanNotDelete` is almost
    always the one you want.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the cluster."
}

variable "timeouts" {
  type = object({
    create = optional(string, "90m")
    read   = optional(string, null)
    update = optional(string, "90m")
    delete = optional(string, "90m")
  })
  default     = {}
  description = <<-EOT
    How long each operation on the cluster is allowed to take.

    The defaults are 90 minutes, matching what the AzureRM provider budgets for
    a managed cluster, rather than AzAPI's generic 30. Thirty minutes is not
    enough for this resource: a private cluster with a bring-your-own DNS zone
    and customer-managed etcd encryption regularly runs past it on create, and
    an upgrade rolls every pool a node at a time.

    A timeout is a ceiling, not a wait — a fast operation still returns fast.
    The only thing a longer one costs is how long a genuinely stuck call takes
    to give up. `read` left null takes AzAPI's default.
  EOT
  nullable    = false
}
