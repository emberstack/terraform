output "variables" {
  description = "Map of organization Actions variables, keyed by variable name."
  value = {
    for k, v in github_actions_organization_variable.this : k => {
      name  = v.variable_name
      value = v.value
    }
  }
}
