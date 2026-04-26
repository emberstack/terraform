resource "github_actions_environment_secret" "this" {
  for_each        = nonsensitive(toset(keys(var.secrets)))
  repository      = var.repository
  environment     = var.environment
  secret_name     = each.value
  plaintext_value = var.secrets[each.value]
}
