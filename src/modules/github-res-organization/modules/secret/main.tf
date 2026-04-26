# =============================================================================
# GITHUB ORGANIZATION ACTIONS SECRET
# =============================================================================
# Manages organization-level GitHub Actions secrets. Accepts a map so the
# submodule can be called once from the parent or standalone via Terragrunt.
# =============================================================================

resource "github_actions_organization_secret" "this" {
  for_each = nonsensitive(toset(keys(var.secrets)))

  secret_name     = each.value
  plaintext_value = var.secrets[each.value].value
  visibility      = var.secrets[each.value].visibility
}
