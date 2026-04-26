resource "github_actions_environment_variable" "this" {
  for_each      = var.variables
  repository    = var.repository
  environment   = var.environment
  variable_name = each.key
  value         = each.value
}
