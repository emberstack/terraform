variable "secrets" {
  description = <<-EOT
    Organization-level Actions secrets to manage.

    Map of `<secret-name> => { value, visibility }`. Each entry creates a
    `github_actions_organization_secret` resource. Values are write-only and
    never exposed in outputs or state diffs.

    Examples:
      secrets = {
        API_KEY = { value = "sk-...", visibility = "all" }
      }
  EOT

  type = map(object({
    value      = string
    visibility = optional(string, "all")
  }))
  sensitive = true

  validation {
    condition = alltrue([
      for k, v in var.secrets :
      contains(["all", "private", "selected"], v.visibility)
    ])
    error_message = "Each secret's visibility must be one of: all, private, selected."
  }
}
