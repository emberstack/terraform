# =============================================================================
# GITHUB ORGANIZATION ACTIONS VARIABLE
# =============================================================================
# Manages organization-level GitHub Actions variables. Accepts a map so the
# submodule can be called once from the parent or standalone via Terragrunt.
# =============================================================================

resource "github_actions_organization_variable" "this" {
  for_each = var.variables

  variable_name = each.key
  value         = each.value.value
  visibility    = each.value.visibility
}
