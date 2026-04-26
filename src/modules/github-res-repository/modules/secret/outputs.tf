output "secrets" {
  description = "Managed secrets keyed by the input map key, each carrying its `name`. Secret values are never returned by GitHub and are not exposed here."
  value = { for key, secret in github_actions_secret.this : key => {
    name = secret.secret_name
  } }
}
