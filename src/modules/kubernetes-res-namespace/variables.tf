variable "name" {
  type        = string
  description = "Namespace name. A DNS-1123 label: lowercase alphanumerics and '-', starting and ending alphanumeric, at most 63 characters."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 63
    error_message = "name must be between 1 and 63 characters."
  }

  validation {
    condition     = can(regex("^[a-z0-9]([-a-z0-9]*[a-z0-9])?$", var.name))
    error_message = "name must be a lowercase DNS label: alphanumerics and '-', starting and ending alphanumeric."
  }
}

variable "labels" {
  type        = map(string)
  description = "Labels applied to the namespace. Pod Security Admission is configured here — `pod-security.kubernetes.io/enforce` and friends are ordinary namespace labels."
  default     = {}
  nullable    = false
}

variable "annotations" {
  type        = map(string)
  description = "Annotations applied to the namespace."
  default     = {}
  nullable    = false
}

variable "wait_for_default_service_account" {
  type        = bool
  description = "Wait for the namespace's default ServiceAccount to be created before returning. A workload applied immediately after the namespace can otherwise find no account to schedule against."
  default     = null
}

variable "timeouts" {
  type = object({
    delete = optional(string)
  })
  description = "Terraform-level operation timeouts as duration strings, e.g. `10m`. Only `delete` is carried — it is the one operation the provider bounds on this resource. A namespace delete blocks on finalizers, so without a bound a wedged resource hangs the apply rather than failing it."
  default     = null

  validation {
    condition     = var.timeouts == null || var.timeouts.delete == null || can(regex("^([0-9]+(\\.[0-9]+)?(ns|us|ms|s|m|h))+$", var.timeouts.delete))
    error_message = "timeouts.delete must be a Go duration string, e.g. '90s', '10m' or '1h30m'."
  }
}
