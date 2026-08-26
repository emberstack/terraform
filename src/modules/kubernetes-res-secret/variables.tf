# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Secret name. A DNS-1123 subdomain: lowercase alphanumerics, '-' and '.', starting and ending alphanumeric, at most 253 characters."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 253
    error_message = "name must be between 1 and 253 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", var.name))
    error_message = "name must be a lowercase DNS subdomain: alphanumerics, '-' and '.', starting and ending alphanumeric."
  }
}

variable "namespace" {
  type        = string
  description = "Namespace the Secret is created in. It must already exist — create one with `kubernetes-res-namespace` and pass its `name` output."
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

variable "type" {
  type        = string
  description = <<-EOT
    Secret type, e.g. `Opaque`, `kubernetes.io/tls`, `kubernetes.io/dockerconfigjson`.

    ⚠️ Required, with no default, on purpose. `type` is IMMUTABLE in Kubernetes, so changing it
    forces a delete-and-recreate. Left optional, an omitted `type` resolves to `Opaque`, and adopting
    an existing `kubernetes.io/tls` Secret then plans a replace that destroys the certificate —
    MEASURED, see the family guide. Making the caller state it turns a silent destroy into a
    question.

    Deliberately not validated against a fixed list: Kubernetes accepts arbitrary custom types, and a
    `contains(...)` here would reject working configurations.
  EOT
  nullable    = false

  validation {
    condition     = length(var.type) > 0
    error_message = "type must not be empty."
  }
}

# -----------------------------------------------------------------------------
# Metadata
# -----------------------------------------------------------------------------

variable "labels" {
  type        = map(string)
  description = "Labels applied to the Secret. ⚠️ Authoritative: labels present on an existing Secret but absent here are REMOVED. Adopting a cert-manager Secret without carrying over `controller.cert-manager.io/fao` strips it."
  default     = {}
  nullable    = false
}

variable "annotations" {
  type        = map(string)
  description = "Annotations applied to the Secret — reflector's `reflector.v1.k8s.emberstack.com/*` keys go here. ⚠️ Authoritative: annotations present on an existing Secret but absent here are REMOVED, which on a cert-manager Secret means losing the eight `cert-manager.io/*` keys it records the issued certificate with."
  default     = {}
  nullable    = false
}

variable "immutable" {
  type        = bool
  description = "Mark the Secret immutable. Kubernetes then rejects every update to its content, so changing the data requires replacing the Secret — and every pod mounting it has to be restarted to see the new one."
  default     = null
}

# -----------------------------------------------------------------------------
# Content
# -----------------------------------------------------------------------------

variable "data" {
  type        = map(string)
  description = "Secret content as PLAINTEXT — the provider base64-encodes it. Passing already-encoded values here double-encodes them. Written to state; use `data_wo` to keep material out of the state file. ⚠️ Computed: removing this input does not empty the Secret — the plan reports no change and the content stays in the cluster. Pass `{}` to clear it."
  default     = null
  sensitive   = true

  # The API server rejects any other key shape at apply time with
  #   "a valid config key must consist of alphanumeric characters, '-', '_' or '.'".
  # Checking it here fails the plan instead, using the regex the server itself reports.
  validation {
    condition     = var.data == null || alltrue([for key in keys(var.data) : can(regex("^[-._a-zA-Z0-9]+$", key))])
    error_message = "data keys must match ^[-._a-zA-Z0-9]+$ — alphanumerics, '-', '_' and '.' only."
  }
}

variable "binary_data" {
  type        = map(string)
  description = "Secret content that is ALREADY base64-encoded, for bytes that are not valid UTF-8. Written to state; use `binary_data_wo` to keep material out of the state file."
  default     = null
  sensitive   = true

  # Content is deliberately NOT checked with `can(base64decode(...))`. MEASURED:
  # base64decode("/w==") returns false — Terraform errors when the decoded bytes are
  # not valid UTF-8, which is precisely the content this input exists to carry. The
  # check would reject working configurations.

  # The API server rejects any other key shape at apply time with
  #   "a valid config key must consist of alphanumeric characters, '-', '_' or '.'".
  # Checking it here fails the plan instead, using the regex the server itself reports.
  validation {
    condition     = var.binary_data == null || alltrue([for key in keys(var.binary_data) : can(regex("^[-._a-zA-Z0-9]+$", key))])
    error_message = "binary_data keys must match ^[-._a-zA-Z0-9]+$ — alphanumerics, '-', '_' and '.' only."
  }
}

variable "data_wo" {
  type        = map(string)
  description = "Plaintext content, write-only: sent to the API server and then discarded, never written to state. Terraform cannot read it back, so it cannot notice a change — `data_wo_revision` is what re-sends it."
  default     = null

  # Not marked `sensitive`: a write-only attribute is never persisted to state
  # nor shown in plan output, so the mark protects nothing — and marking it
  # propagates a sensitivity mark onto the attribute even when null, which
  # Terraform reads as a change. That surfaces as a spurious in-place update on
  # every Secret adopted from a module that did not set this attribute.

  # The API server rejects any other key shape at apply time with
  #   "a valid config key must consist of alphanumeric characters, '-', '_' or '.'".
  # Checking it here fails the plan instead, using the regex the server itself reports.
  validation {
    condition     = var.data_wo == null || alltrue([for key in keys(var.data_wo) : can(regex("^[-._a-zA-Z0-9]+$", key))])
    error_message = "data_wo keys must match ^[-._a-zA-Z0-9]+$ — alphanumerics, '-', '_' and '.' only."
  }
}

variable "data_wo_revision" {
  type        = number
  description = "Revision counter for `data_wo`. Bump it to re-send write-only content; rotating a secret without bumping it is a silent no-op."
  default     = null

  # Same trap as the helm module's `set_wo`: without the revision, Terraform has
  # nothing to compare, so a rotated secret plans clean and never reaches the
  # cluster.
  validation {
    condition     = var.data_wo == null || length(var.data_wo) == 0 || var.data_wo_revision != null
    error_message = "data_wo_revision is required when data_wo is used, otherwise changes to write-only content never reach the cluster."
  }
}

variable "binary_data_wo" {
  type        = map(string)
  description = "Base64-encoded content, write-only: sent to the API server and then discarded, never written to state. Paired with `binary_data_wo_revision`."
  default     = null

  # Not marked `sensitive`: a write-only attribute is never persisted to state
  # nor shown in plan output, so the mark protects nothing — and marking it
  # propagates a sensitivity mark onto the attribute even when null, which
  # Terraform reads as a change. That surfaces as a spurious in-place update on
  # every Secret adopted from a module that did not set this attribute.

  # Content is deliberately NOT checked with `can(base64decode(...))`. MEASURED:
  # base64decode("/w==") returns false — Terraform errors when the decoded bytes are
  # not valid UTF-8, which is precisely the content this input exists to carry. The
  # check would reject working configurations.

  # The API server rejects any other key shape at apply time with
  #   "a valid config key must consist of alphanumeric characters, '-', '_' or '.'".
  # Checking it here fails the plan instead, using the regex the server itself reports.
  validation {
    condition     = var.binary_data_wo == null || alltrue([for key in keys(var.binary_data_wo) : can(regex("^[-._a-zA-Z0-9]+$", key))])
    error_message = "binary_data_wo keys must match ^[-._a-zA-Z0-9]+$ — alphanumerics, '-', '_' and '.' only."
  }
}

variable "binary_data_wo_revision" {
  type        = number
  description = "Revision counter for `binary_data_wo`. Bump it to re-send write-only content."
  default     = null

  validation {
    condition     = var.binary_data_wo == null || length(var.binary_data_wo) == 0 || var.binary_data_wo_revision != null
    error_message = "binary_data_wo_revision is required when binary_data_wo is used, otherwise changes to write-only content never reach the cluster."
  }
}

# -----------------------------------------------------------------------------
# Behaviour
# -----------------------------------------------------------------------------

variable "wait_for_service_account_token" {
  type        = bool
  description = "For a `kubernetes.io/service-account-token` Secret, wait for the API server to populate the token before returning. Meaningless for any other type."
  default     = null
}

variable "timeouts" {
  type = object({
    create = optional(string)
  })
  description = "Terraform-level operation timeouts as duration strings, e.g. `2m`. Only `create` is carried — it is the one operation the provider bounds on this resource."
  default     = null

  validation {
    condition     = var.timeouts == null || var.timeouts.create == null || can(regex("^([0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h))+$", var.timeouts.create))
    error_message = "timeouts.create must be a Go duration string, e.g. '90s', '2m' or '1h30m'."
  }
}
