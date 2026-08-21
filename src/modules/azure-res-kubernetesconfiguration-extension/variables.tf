# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the extension instance on the cluster."
  nullable    = false

  # The spec declares `extensionName` as a plain string with no pattern, so only a
  # length bound is checked. Extension types that derive in-cluster object names
  # from it impose their own rules, which are theirs to enforce and not ARM's.
  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 253
    error_message = "name must be 1–253 characters."
  }
}

variable "cluster_resource_id" {
  type        = string
  description = <<-EOT
    ARM resource ID of the cluster the extension is installed on. Becomes the
    resource's `parent_id`.

    Any cluster resource provider the extensions RP accepts works — AKS
    (`Microsoft.ContainerService/managedClusters`), Arc
    (`Microsoft.Kubernetes/connectedClusters`), AKS hybrid
    (`Microsoft.HybridContainerService/provisionedClusters`) and
    `Microsoft.ResourceConnector/appliances`.
  EOT
  nullable    = false

  # Six segments, matching the RP's own route: /subscriptions/{s}/resourceGroups/
  # {rg}/providers/{clusterRp}/{clusterResourceName}/{clusterName}. Case is folded
  # because ARM segment names are case-insensitive. The cluster RP itself is not
  # checked against a list — that list grows, and a stale one here would reject a
  # working configuration.
  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/[^/]+/[^/]+/[^/]+$", var.cluster_resource_id))
    error_message = "cluster_resource_id must be a full cluster resource ID, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.ContainerService/managedClusters/<cluster>."
  }
}

variable "extension_type" {
  type        = string
  description = <<-EOT
    Extension type to install, as registered with Microsoft.KubernetesConfiguration
    by its publisher — e.g. `microsoft.flux`, `Microsoft.AppConfiguration`. Casing
    is the publisher's own and is not normalised here.

    Immutable: changing it replaces the extension. List what a cluster can take
    with `az k8s-extension extension-types list --cluster-type managedClusters`.
  EOT
  nullable    = false

  validation {
    condition     = length(var.extension_type) > 0
    error_message = "extension_type must not be empty."
  }
}

# -----------------------------------------------------------------------------
# Optional — scope
# -----------------------------------------------------------------------------

variable "scope" {
  type = object({
    kind      = string
    namespace = optional(string, null)
  })
  default     = { kind = "cluster" }
  description = <<-EOT
    Where the extension is installed. Immutable: changing it replaces the extension.

    - `kind`: `cluster` (one instance serving the whole cluster) or `namespace`
      (one instance per namespace). Which of the two an extension type supports is
      fixed by its publisher — `microsoft.flux`, for one, is cluster-only.
    - `namespace`: for `cluster`, the release namespace the extension is deployed
      into; for `namespace`, the target namespace it manages. Either way the
      namespace is created if it does not exist. Optional — left unset, the
      resource provider picks the extension type's own default.
  EOT
  nullable    = false

  validation {
    condition     = contains(["cluster", "namespace"], var.scope.kind)
    error_message = "scope.kind must be one of: cluster, namespace."
  }
}

# -----------------------------------------------------------------------------
# Optional — version and upgrades
# -----------------------------------------------------------------------------

variable "auto_upgrade_minor_version" {
  type        = bool
  default     = true
  description = <<-EOT
    Whether the extension takes minor-version upgrades automatically. Default: true,
    matching ARM's own default.

    Mutually exclusive with `extension_version`: ARM only honours a pinned version
    while this is false.
  EOT
  nullable    = false
}

variable "release_train" {
  type        = string
  default     = "Stable"
  description = <<-EOT
    Release train auto-upgrade follows — typically `Stable` or `Preview`, though the
    set is per extension type and not published in the ARM schema, so it is not
    validated here.

    Only sent while `auto_upgrade_minor_version` is true; ARM ignores it otherwise.
  EOT
  nullable    = false
}

variable "extension_version" {
  type        = string
  default     = null
  description = <<-EOT
    Exact extension version to pin. Requires `auto_upgrade_minor_version = false`.

    Named `extension_version` rather than `version`, which Terraform reserves and
    will not accept as a variable name.
  EOT

  validation {
    condition     = var.extension_version == null || !var.auto_upgrade_minor_version
    error_message = "extension_version requires auto_upgrade_minor_version = false — ARM only pins a version while auto-upgrade is off."
  }
}

variable "auto_upgrade_mode" {
  type        = string
  default     = null
  description = <<-EOT
    How far an automatic upgrade is allowed to move: `none`, `patch` or `compatible`.
    Left unset the property is not sent, and ARM applies its own default
    (`compatible`).

    Newer than the rest of the upgrade surface — not every extension type honours it.
  EOT

  validation {
    # `contains` rejects a null needle outright, so the null guard is load-bearing
    # rather than cosmetic — `||` short-circuits and never reaches the second half.
    condition     = var.auto_upgrade_mode == null || contains(["none", "patch", "compatible"], var.auto_upgrade_mode)
    error_message = "auto_upgrade_mode must be one of: none, patch, compatible."
  }
}

# -----------------------------------------------------------------------------
# Optional — configuration
# -----------------------------------------------------------------------------

variable "configuration_settings" {
  type        = map(string)
  default     = {}
  description = <<-EOT
    Extension configuration, as ARM name-value pairs. Untyped on purpose: this is a
    flat `map(string)` in the ARM contract itself, with dotted keys standing in for
    Helm value paths (`multiTenancy.enforce`, `global.clusterType`). Which keys an
    extension accepts is published by the extension, not by ARM.

    Values are visible in state and in plan output. Anything sensitive belongs in
    `configuration_protected_settings`.
  EOT
  nullable    = false
}

variable "configuration_protected_settings" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = <<-EOT
    Sensitive extension configuration, as ARM name-value pairs. Write-only: ARM
    never returns these, so Terraform cannot detect that they changed on the service
    side, and cannot detect that the values here changed either — see
    `configuration_protected_settings_version`.
  EOT
  nullable    = false
}

variable "configuration_protected_settings_version" {
  type        = string
  default     = "1"
  description = <<-EOT
    Opaque marker for the contents of `configuration_protected_settings`. Change it
    to any different string to force the current values to be pushed to ARM.

    Needed because protected settings live in AzAPI's `sensitive_body`, which is
    excluded from plan comparison — rotating a secret without changing this leaves
    the old value in the cluster with a clean plan. Ignored when
    `configuration_protected_settings` is empty.
  EOT
  nullable    = false

  validation {
    condition     = length(var.configuration_protected_settings_version) > 0
    error_message = "configuration_protected_settings_version must not be empty."
  }
}

# -----------------------------------------------------------------------------
# Optional — identity
# -----------------------------------------------------------------------------

variable "managed_identities" {
  type = object({
    system_assigned = optional(bool, false)
  })
  default     = {}
  description = <<-EOT
    Managed identity configuration for the extension. Immutable: changing it
    replaces the extension.

    - `system_assigned`: enable a system-assigned identity on the extension resource.

    Carries no `user_assigned_resource_ids`, unlike its siblings in this family:
    `Microsoft.KubernetesConfiguration/extensions` types its `identity` as the v3
    common-types `Identity`, whose only accepted value is `SystemAssigned`.

    Usually left alone on AKS, where the resource provider assigns an identity to
    extension types that need one and reports it as `properties.aksAssignedIdentity`.
    The `principal_id` output resolves whichever of the two exists.
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — marketplace
# -----------------------------------------------------------------------------

variable "plan" {
  type = object({
    name           = string
    publisher      = string
    product        = string
    promotion_code = optional(string, null)
    version        = optional(string, null)
  })
  default     = null
  description = <<-EOT
    Marketplace plan, for extensions published through Azure Marketplace. Immutable:
    changing it replaces the extension.

    `name`, `publisher` and `product` are required by ARM when a plan is present.
    The marketplace terms for the offer must already be accepted on the
    subscription — the extension PUT fails otherwise, and accepting them is not
    something this module does.
  EOT
}

# -----------------------------------------------------------------------------
# Optional — access
# -----------------------------------------------------------------------------

variable "identity_role_assignments" {
  type = map(object({
    name                                   = optional(string, null)
    role_definition_id_or_name             = string
    scope                                  = optional(string, null)
    description                            = optional(string, null)
    condition                              = optional(string, null)
    condition_version                      = optional(string, null)
    delegated_managed_identity_resource_id = optional(string, null)
  }))
  default     = {}
  description = <<-EOT
    Role assignments granted to the **extension's own identity**, keyed by stable
    name. Defaults to `cluster_resource_id` when `scope` is null.

    Use this for the rights the extension needs to run — `AcrPull` on a registry,
    `Key Vault Secrets User` on a vault, a data-plane role on the service it
    reconciles.

    The principal is the AKS-assigned identity where the resource provider creates
    one, otherwise the extension's system-assigned identity. Both are unknown until
    apply, and an extension with neither fails a precondition rather than sending a
    null principal to ARM.

    `role_definition_id_or_name` accepts either a role display name or an ARM
    role-definition resource ID — auto-routed by the leading `/`.

    Every assignment is sent with `principalType = "ServicePrincipal"`, since the
    principal is always a managed identity, so ARM skips the directory lookup that
    fails on a freshly created principal.
  EOT
  nullable    = false

  validation {
    condition = alltrue([
      for assignment in var.identity_role_assignments :
      assignment.name == null || can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", assignment.name))
    ])
    error_message = "identity_role_assignments `name`, when supplied, must be a lowercase GUID (e.g. 11111111-1111-1111-1111-111111111111)."
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
    Resource lock configuration on the extension.

    - `kind`: `CanNotDelete` or `ReadOnly`.
    - `name`: optional. Defaults to `lock-<extension-name>`.

    Worth setting on an extension whose removal takes workloads with it — deleting
    a GitOps extension stops reconciliation of everything it manages.
  EOT

  validation {
    condition     = var.lock == null || contains(["CanNotDelete", "ReadOnly"], try(var.lock.kind, ""))
    error_message = "lock.kind must be one of: CanNotDelete, ReadOnly."
  }
}

# -----------------------------------------------------------------------------
# Optional — lifecycle
# -----------------------------------------------------------------------------

variable "force_delete" {
  type        = bool
  default     = false
  description = <<-EOT
    Whether a delete is sent with ARM's `forceDelete` query parameter. Default: false.

    ARM's normal delete is asynchronous and waits for the extension agent to
    uninstall the release in the cluster. That never returns when the release is
    wedged, or when the cluster is unreachable, and the destroy hangs until it
    times out.

    `forceDelete = true` removes the ARM resource without that handshake. **The
    in-cluster objects are left behind** — a Helm release, a namespace, CRDs and
    whatever they own — and re-installing the same extension type afterwards
    collides with them. Turn it on to break a stuck destroy, then clean up the
    cluster by hand.
  EOT
  nullable    = false
}
