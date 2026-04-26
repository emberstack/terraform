resource "github_actions_secret" "this" {
  for_each        = nonsensitive(toset(keys(var.secrets)))
  repository      = var.repository
  secret_name     = each.value
  plaintext_value = var.secrets[each.value]
}
