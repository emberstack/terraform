variable "name" {
  description = "Login name of the GitHub organization."
  type        = string

  validation {
    condition     = length(var.name) > 0
    error_message = "name must not be empty."
  }
}

variable "display_name" {
  description = "Display name of the organization. Defaults to `name` when null."
  type        = string
  default     = null
}

variable "billing_email" {
  description = "Billing email address for the organization."
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.billing_email))
    error_message = "billing_email must be a valid email address."
  }
}

variable "location" {
  description = "Geographic location of the organization."
  type        = string
  default     = null
}

variable "blog" {
  description = "URL of the organization's blog."
  type        = string
  default     = null
}

variable "default_repository_permission" {
  description = "Default permission level for organization members on new repositories. One of: read, write, admin, none."
  type        = string
  default     = "read"

  validation {
    condition     = contains(["read", "write", "admin", "none"], var.default_repository_permission)
    error_message = "default_repository_permission must be one of: read, write, admin, none."
  }
}

variable "members_can_create_repositories" {
  description = "Whether members can create repositories."
  type        = bool
  default     = true
}

variable "members_can_create_public_repositories" {
  description = "Whether members can create public repositories."
  type        = bool
  default     = false
}

variable "members_can_create_private_repositories" {
  description = "Whether members can create private repositories."
  type        = bool
  default     = true
}

variable "members_can_create_internal_repositories" {
  description = "Whether members can create internal repositories."
  type        = bool
  default     = true
}

variable "members_can_fork_private_repositories" {
  description = "Whether members can fork private repositories."
  type        = bool
  default     = false
}

variable "has_organization_projects" {
  description = "Whether organization projects are enabled."
  type        = bool
  default     = false
}

variable "has_repository_projects" {
  description = "Whether repository projects are enabled."
  type        = bool
  default     = false
}

variable "dependabot_alerts_enabled_for_new_repositories" {
  description = "Whether Dependabot alerts are automatically enabled for new repositories."
  type        = bool
  default     = null
}

variable "dependabot_security_updates_enabled_for_new_repositories" {
  description = "Whether Dependabot security updates are automatically enabled for new repositories."
  type        = bool
  default     = null
}

variable "dependency_graph_enabled_for_new_repositories" {
  description = "Whether the dependency graph is automatically enabled for new repositories."
  type        = bool
  default     = null
}

variable "allowed_actions" {
  description = "Actions permission policy. One of: all, local_only, selected."
  type        = string
  default     = "all"

  validation {
    condition     = contains(["all", "local_only", "selected"], var.allowed_actions)
    error_message = "allowed_actions must be one of: all, local_only, selected."
  }
}

variable "enabled_repositories" {
  description = "Repository access policy for GitHub Actions. One of: all, none, selected."
  type        = string
  default     = "all"

  validation {
    condition     = contains(["all", "none", "selected"], var.enabled_repositories)
    error_message = "enabled_repositories must be one of: all, none, selected."
  }
}

variable "enabled_repository_ids" {
  description = "List of repository IDs enabled for GitHub Actions when `enabled_repositories` is `selected`."
  type        = list(number)
  default     = []
  nullable    = false

  validation {
    condition     = var.enabled_repositories != "selected" || length(var.enabled_repository_ids) > 0
    error_message = "enabled_repository_ids must list at least one repository when enabled_repositories is \"selected\"."
  }
}

variable "allowed_actions_config" {
  description = <<-EOT
    Which actions are permitted when `allowed_actions` is `selected`. Required in
    that case and must be omitted otherwise.
      - `github_owned_allowed` — allow actions published by GitHub.
      - `verified_allowed`     — allow actions from verified Marketplace creators.
      - `patterns_allowed`     — additional `owner/repo@ref` patterns to allow.
  EOT
  type = object({
    github_owned_allowed = bool
    verified_allowed     = optional(bool)
    patterns_allowed     = optional(set(string))
  })
  default = null

  validation {
    condition     = var.allowed_actions != "selected" || var.allowed_actions_config != null
    error_message = "allowed_actions_config must be set when allowed_actions is \"selected\"."
  }
}

variable "default_workflow_permissions" {
  description = "Default GITHUB_TOKEN permissions for Actions workflows. One of: read, write."
  type        = string
  default     = "read"

  validation {
    condition     = contains(["read", "write"], var.default_workflow_permissions)
    error_message = "default_workflow_permissions must be one of: read, write."
  }
}

variable "can_approve_pull_request_reviews" {
  description = "Whether GitHub Actions can approve pull request reviews."
  type        = bool
  default     = false
}

variable "variables" {
  description = <<-EOT
    Organization-level Actions variables.

    Map of `<variable-name> => { value, visibility }`. Each entry creates a
    `github_actions_organization_variable` resource.

    Examples:
      variables = {
        ENVIRONMENT = { value = "production", visibility = "all" }
        REGION      = { value = "westeurope" }
      }
  EOT

  type = map(object({
    value      = string
    visibility = optional(string, "all")
  }))
  default = {}

  validation {
    condition = alltrue([
      for k, v in var.variables :
      contains(["all", "private", "selected"], v.visibility)
    ])
    error_message = "Each variable's visibility must be one of: all, private, selected."
  }
}

variable "secrets" {
  description = <<-EOT
    Organization-level Actions secrets.

    Map of `<secret-name> => { value, visibility }`. Each entry creates a
    `github_actions_organization_secret` resource.

    Values are submitted as plaintext and are therefore **persisted in Terraform
    state** — protect the state backend accordingly. They are marked sensitive so
    they stay out of plan output and module outputs, but that is redaction, not
    absence. GitHub never returns secret values, so changes made outside
    Terraform are not detected.

    Examples:
      secrets = {
        API_KEY = { value = "sk-...", visibility = "all" }
      }
  EOT

  type = map(object({
    value      = string
    visibility = optional(string, "all")
  }))
  default   = {}
  sensitive = true

  validation {
    condition = alltrue([
      for k, v in var.secrets :
      contains(["all", "private", "selected"], v.visibility)
    ])
    error_message = "Each secret's visibility must be one of: all, private, selected."
  }
}
