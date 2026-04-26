output "secrets" {
  description = "The environment secrets."
  value = {
    for key, secret in github_actions_environment_secret.this : key => {
      name = secret.secret_name
    }
  }
}
