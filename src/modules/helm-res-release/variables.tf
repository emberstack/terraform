# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Helm release name. Helm rejects anything longer than 53 characters, because the name has to fit inside the labels it generates."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 53
    error_message = "name must be between 1 and 53 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.name))
    error_message = "name must be a lowercase DNS subdomain: alphanumerics, '-' and '.', starting and ending alphanumeric."
  }
}

variable "namespace" {
  type        = string
  description = "Namespace to install the release into. Unless `create_namespace` is set it must already exist — create one with `kubernetes-res-namespace` and pass its `name` output."
  nullable    = false

  validation {
    condition     = length(var.namespace) >= 1 && length(var.namespace) <= 63
    error_message = "namespace must be between 1 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.namespace))
    error_message = "namespace must be a lowercase DNS label: alphanumerics and '-', starting and ending alphanumeric."
  }
}

variable "chart" {
  type        = string
  description = <<-EOT
    Chart to install. Three forms are accepted:

    - A chart name resolved against `repository`, e.g. `traefik`
    - A full OCI reference with `repository` left null, e.g. `oci://ghcr.io/emberstack/helm-charts/generic`
    - A path to an unpacked chart on the machine running Terraform, e.g. `./charts/example`
  EOT
  nullable    = false

  validation {
    condition     = length(var.chart) > 0
    error_message = "chart must not be empty."
  }
}

# -----------------------------------------------------------------------------
# Chart source
# -----------------------------------------------------------------------------

variable "repository" {
  type        = string
  description = "Repository URL the chart name is resolved against. Leave null when `chart` is a full OCI reference or a local path."
  default     = null

  validation {
    condition     = var.repository == null || can(regex("^(https?|oci)://", var.repository))
    error_message = "repository must be an http://, https:// or oci:// URL."
  }
}

variable "chart_version" {
  type        = string
  description = "Chart version to install. Null resolves to the latest version at apply time, which makes the release irreproducible — pin it. Named `chart_version` because Terraform reserves `version` for module blocks."
  default     = null
}

variable "devel" {
  type        = bool
  description = "Allow prerelease chart versions to satisfy the version constraint. Helm ignores this once `chart_version` is set."
  default     = null
}

variable "verify" {
  type        = bool
  description = "Verify the chart's provenance file before installing."
  default     = null
}

variable "keyring" {
  type        = string
  description = "Path to the public keyring `verify` checks the provenance file against."
  default     = null
}

variable "repository_username" {
  type        = string
  description = "Username for a repository that requires authentication."
  default     = null
}

variable "repository_password" {
  type        = string
  description = "Password for a repository that requires authentication. Redacted from plan output but written to state — see the note on secrets in `main.tf`."
  default     = null
  sensitive   = true
}

variable "repository_ca_file" {
  type        = string
  description = "Path to a CA bundle used to verify the repository's TLS certificate."
  default     = null
}

variable "repository_cert_file" {
  type        = string
  description = "Path to a client certificate presented to the repository."
  default     = null
}

variable "repository_key_file" {
  type        = string
  description = "Path to the private key belonging to `repository_cert_file`."
  default     = null
}

variable "pass_credentials" {
  type        = bool
  description = "Keep sending the repository credentials to hosts the download is redirected to. Helm defaults this off because a redirect can point anywhere."
  default     = null
}

# -----------------------------------------------------------------------------
# Values
# -----------------------------------------------------------------------------
# Helm merges these lowest to highest: `values`, then `values_yaml` in order,
# then `set`, `set_list`, `set_sensitive` and `set_wo`. That ordering is Helm's,
# not a choice this module makes.

variable "values" {
  type        = any
  description = "Chart values as an HCL object, rendered to YAML. Typed `any` rather than a map on purpose: values of different shapes have no common element type, so a map constraint would reject valid input."
  default     = {}

  validation {
    condition     = var.values == null || can(keys(var.values))
    error_message = "values must be an object or a map."
  }
}

variable "values_yaml" {
  type        = list(string)
  description = "Raw YAML documents merged after `values`, in order — the equivalent of repeating `helm -f`. Use it for values copied verbatim from a chart's documentation."
  default     = []
  nullable    = false
}

variable "set" {
  type = list(object({
    name  = string
    value = optional(string)
    type  = optional(string)
  }))
  description = "Individual values addressed by dotted path, equivalent to `helm --set`. `type` is `auto` or `string`."
  default     = null

  validation {
    condition     = var.set == null || alltrue([for entry in var.set : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "set[*].type must be either 'auto' or 'string'."
  }
}

variable "set_list" {
  type = list(object({
    name  = string
    value = list(string)
  }))
  description = "List values addressed by dotted path, equivalent to `helm --set-list`."
  default     = null
}

variable "set_sensitive" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  description = "Values redacted from plan output. Still written to state in cleartext — use `set_wo` for material that must not land there."
  default     = null

  # Not marked `sensitive` here: the provider schema already marks
  # `set_sensitive.value`, so the redaction is in place either way. Marking the
  # variable as well propagates a sensitivity mark onto the attribute even when
  # it is null, and Terraform reads a changed mark as a change — which shows up
  # as a spurious in-place update on every release adopted from a module that
  # did not set this attribute.

  validation {
    condition     = var.set_sensitive == null || alltrue([for entry in var.set_sensitive : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "set_sensitive[*].type must be either 'auto' or 'string'."
  }
}

variable "set_wo" {
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  description = "Write-only values: sent to Helm, then discarded, never written to state. Terraform cannot read them back, so it cannot notice one changed — `set_wo_revision` is what re-sends them."
  default     = null

  # Not marked `sensitive`, for the reason given on `set_sensitive`. Write-only
  # attributes are never persisted or displayed regardless, so the mark buys
  # nothing here and costs a spurious diff on adoption.

  validation {
    condition     = var.set_wo == null || alltrue([for entry in var.set_wo : entry.type == null || contains(["auto", "string"], entry.type)])
    error_message = "set_wo[*].type must be either 'auto' or 'string'."
  }
}

variable "set_wo_revision" {
  type        = number
  description = "Revision counter for `set_wo`. Bump it to re-send write-only values; rotating a secret without bumping it is a silent no-op."
  default     = null

  # Helm re-sends write-only values only when this changes. Terraform cannot
  # read one back to compare, so without the revision a rotated secret plans
  # clean and never reaches the cluster — the check is the only thing standing
  # between a caller and a rotation that silently did nothing.
  validation {
    condition     = var.set_wo == null || length(var.set_wo) == 0 || var.set_wo_revision != null
    error_message = "set_wo_revision is required when set_wo is used, otherwise changes to write-only values never reach the cluster."
  }
}

# -----------------------------------------------------------------------------
# Release lifecycle
# -----------------------------------------------------------------------------

variable "create_namespace" {
  type        = bool
  description = "Ask Helm to create `namespace` if it is absent. Helm creates it bare — no labels, no annotations — and leaves it behind on uninstall. A namespace that needs metadata, or that should be removed with what it holds, belongs to `kubernetes-res-namespace` instead."
  default     = false
  nullable    = false
}

variable "upgrade_install" {
  type        = bool
  description = "Upgrade the release when one of the same name already exists instead of failing. Makes a first apply idempotent against a release installed out of band."
  default     = null
}

variable "atomic" {
  type        = bool
  description = "Roll the release back to its previous revision if the install or upgrade fails."
  default     = null
}

variable "cleanup_on_fail" {
  type        = bool
  description = "Delete resources created during a failed upgrade."
  default     = null
}

variable "wait" {
  type        = bool
  description = "Block until every resource in the release reports ready, or `timeout` elapses."
  default     = null
}

variable "wait_for_jobs" {
  type        = bool
  description = "Additionally block until Jobs in the release have completed. Has no effect unless `wait` is true."
  default     = null
}

variable "timeout" {
  type        = number
  description = "Seconds to wait for any individual Kubernetes operation."
  default     = null

  validation {
    condition     = var.timeout == null || var.timeout > 0
    error_message = "timeout must be greater than 0 seconds."
  }
}

variable "max_history" {
  type        = number
  description = "Maximum number of release revisions Helm retains. 0 keeps every revision, and each one is a Secret in the release namespace."
  default     = null

  validation {
    condition     = var.max_history == null || var.max_history >= 0
    error_message = "max_history must be 0 or greater."
  }
}

variable "replace" {
  type        = bool
  description = "Reuse the name of a deleted release still present in history. Unsafe in production: it skips the usual name-collision check."
  default     = null
}

variable "force_update" {
  type        = bool
  description = "Replace resources through delete-and-recreate when an in-place update is rejected. Destroys and rebuilds the affected objects."
  default     = null
}

variable "recreate_pods" {
  type        = bool
  description = "Restart the release's pods on upgrade or rollback. A blunt instrument — every pod in the release goes down and comes back rather than rolling, so it is downtime by design. The usual alternative is a checksum annotation on the pod template, which most charts already carry."
  default     = null
}

variable "reset_values" {
  type        = bool
  description = "Discard the previous revision's values and apply only what this release supplies."
  default     = null
}

variable "reuse_values" {
  type        = bool
  description = "Merge this release's values on top of the previous revision's instead of replacing them."
  default     = null
}

variable "take_ownership" {
  type        = bool
  description = "Adopt pre-existing cluster resources that the chart would otherwise refuse to overwrite."
  default     = null
}

variable "description" {
  type        = string
  description = "Custom description recorded against the release revision, shown by `helm history`."
  default     = null
}

# -----------------------------------------------------------------------------
# Rendering
# -----------------------------------------------------------------------------

variable "skip_crds" {
  type        = bool
  description = "Skip the chart's `crds/` directory. Set this where CRDs are owned elsewhere — a managed add-on, or a separate release — so the chart does not fight over them."
  default     = null
}

variable "disable_crd_hooks" {
  type        = bool
  description = "Prevent CRD hooks from running while the release is installed or upgraded."
  default     = null
}

variable "disable_webhooks" {
  type        = bool
  description = "Prevent the chart's own Helm hooks from running."
  default     = null
}

variable "disable_openapi_validation" {
  type        = bool
  description = "Skip validating rendered templates against the cluster's OpenAPI schema."
  default     = null
}

variable "dependency_update" {
  type        = bool
  description = "Run `helm dependency update` before installing. Applies to local chart paths, which are the only ones with an unresolved `charts/` directory."
  default     = null
}

variable "lint" {
  type        = bool
  description = "Lint the chart before installing."
  default     = null
}

variable "render_subchart_notes" {
  type        = bool
  description = "Include subchart NOTES.txt output in the release notes."
  default     = null
}

variable "postrender" {
  type = object({
    binary_path = string
    args        = optional(list(string))
  })
  description = "Executable run over the rendered manifests before they are applied. The binary has to exist on whatever machine runs Terraform, which is worth weighing before a CI runner depends on it."
  default     = null
}

variable "timeouts" {
  type = object({
    create = optional(string)
    read   = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  description = "Terraform-level operation timeouts as duration strings, e.g. `30m`. All four operations the provider bounds are carried. Distinct from `timeout`, which bounds Helm's wait on individual Kubernetes operations."
  default     = null
}
