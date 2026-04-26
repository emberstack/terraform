variable "variables" {
  description = <<-EOT
    Organization-level Actions variables to manage.

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

  validation {
    condition = alltrue([
      for k, v in var.variables :
      contains(["all", "private", "selected"], v.visibility)
    ])
    error_message = "Each variable's visibility must be one of: all, private, selected."
  }
}
