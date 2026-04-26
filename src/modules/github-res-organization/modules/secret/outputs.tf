output "secrets" {
  description = "Map of organization Actions secret names (values are not exposed)."
  value = {
    for k, v in github_actions_organization_secret.this : k => {
      name = v.secret_name
    }
  }
}
