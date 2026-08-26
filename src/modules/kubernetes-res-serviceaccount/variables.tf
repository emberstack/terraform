# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "ServiceAccount name. A DNS-1123 subdomain: lowercase alphanumerics, '-' and '.', starting and ending alphanumeric, at most 253 characters."
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
  description = "Namespace the ServiceAccount is created in. It must already exist — create one with `kubernetes-res-namespace` and pass its `name` output."
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

# -----------------------------------------------------------------------------
# Metadata
# -----------------------------------------------------------------------------
# Identity federation is configured here rather than through dedicated inputs,
# so the module carries no cloud-specific vocabulary. See the banner in
# `main.tf` for the Azure workload identity pair.

variable "labels" {
  type        = map(string)
  description = "Labels applied to the ServiceAccount — `azure.workload.identity/use = \"true\"` goes here. ⚠️ Authoritative: labels present on an existing account but absent here are REMOVED."
  default     = {}
  nullable    = false
}

variable "annotations" {
  type        = map(string)
  description = "Annotations applied to the ServiceAccount — `azure.workload.identity/client-id` goes here, as does EKS's `eks.amazonaws.com/role-arn`. ⚠️ Authoritative: annotations present on an existing account but absent here are REMOVED."
  default     = {}
  nullable    = false
}

# -----------------------------------------------------------------------------
# Behaviour
# -----------------------------------------------------------------------------

variable "automount_service_account_token" {
  type        = bool
  description = "Mount this account's token into pods that use it. Null leaves the field unset, which Kubernetes reads as true. Setting it false is the blunt way to deny a workload API access — a pod can still opt back in through its own `automountServiceAccountToken`."
  default     = null
}

variable "secrets" {
  type        = set(string)
  description = "Names of Secrets in the same namespace to associate with the account. A set, not a list: order carries no meaning to Kubernetes and a list would invent a diff."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for secret in var.secrets : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", secret))])
    error_message = "every entry in secrets must be a lowercase DNS subdomain."
  }
}

variable "image_pull_secrets" {
  type        = set(string)
  description = "Names of `kubernetes.io/dockerconfigjson` Secrets used to pull images for pods running as this account. The Secrets must live in the same namespace — an imagePullSecret is never resolved across namespaces."
  default     = []
  nullable    = false

  validation {
    condition     = alltrue([for secret in var.image_pull_secrets : can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?(\\.[a-z0-9]([-a-z0-9]*[a-z0-9])?)*$", secret))])
    error_message = "every entry in image_pull_secrets must be a lowercase DNS subdomain."
  }
}

variable "timeouts" {
  type = object({
    create = optional(string)
  })
  description = "Terraform-level operation timeouts as duration strings, e.g. `2m`. Only create is supported by the provider."
  default     = null

  validation {
    condition     = var.timeouts == null || var.timeouts.create == null || can(regex("^([0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h))+$", var.timeouts.create))
    error_message = "timeouts.create must be a Go duration string, e.g. '90s', '2m' or '1h30m'."
  }
}
