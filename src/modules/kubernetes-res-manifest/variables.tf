# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "manifest" {
  type        = any
  description = <<-EOT
    The object to apply, as an HCL object mirroring its YAML.

    Typed `any` rather than a map or a typed object: Terraform unifies map
    element types, and two manifests of different kinds have no common base
    type, so a narrower constraint would reject valid input. Only the three
    fields every Kubernetes object carries are validated here — everything below
    `spec` is the API server's business.
  EOT
  nullable    = false

  validation {
    condition     = can(var.manifest.apiVersion) && can(var.manifest.kind)
    error_message = "manifest must set both apiVersion and kind."
  }

  validation {
    condition     = can(var.manifest.metadata.name)
    error_message = "manifest must set metadata.name. `generate_name` is not supported here: a name known only after apply cannot be referenced by whatever depends on it."
  }
}

# -----------------------------------------------------------------------------
# Apply behaviour
# -----------------------------------------------------------------------------

variable "computed_fields" {
  type        = list(string)
  description = "Manifest paths whose values the API server is allowed to change without it counting as drift. Null leaves the provider's own default in place, which is `[\"metadata.annotations\", \"metadata.labels\"]` — widen it when a controller writes elsewhere in the object, e.g. `status` or a mutating webhook's additions to `spec`."
  default     = null
}

variable "field_manager" {
  type = object({
    name            = optional(string)
    force_conflicts = optional(bool)
  })
  description = "Server-side apply field manager. `force_conflicts` takes ownership of fields another manager already owns — necessary when adopting an object a controller or `kubectl apply` created, and a way to start a tug-of-war if that other writer is still active."
  default     = null
}

variable "wait" {
  type = object({
    rollout = optional(bool)
    fields  = optional(map(string))
    condition = optional(list(object({
      type   = string
      status = string
    })))
  })
  description = "Block the apply until the object reaches a state. `rollout` waits as `kubectl rollout status` does; `fields` maps a manifest path to a regex the value must match; `condition` waits for entries in `status.conditions`. Bound it with `timeouts.create`, or a resource that never reconciles hangs the apply."
  default     = null
}

variable "timeouts" {
  type = object({
    create = optional(string)
    update = optional(string)
    delete = optional(string)
  })
  description = "Terraform-level operation timeouts as duration strings, e.g. `5m`. Worth setting alongside `wait` — without one, waiting on a condition that never arrives blocks until the pipeline gives up rather than failing."
  default     = null

  validation {
    condition = var.timeouts == null || alltrue([
      for timeout in [var.timeouts.create, var.timeouts.update, var.timeouts.delete] :
      timeout == null || can(regex("^([0-9]+([.][0-9]+)?(ns|us|ms|s|m|h))+$", timeout))
    ])
    error_message = "timeouts values must be Go duration strings, e.g. '90s', '5m' or '1h30m'."
  }
}
