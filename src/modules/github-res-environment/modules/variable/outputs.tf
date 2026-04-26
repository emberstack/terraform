output "variables" {
  description = "The environment variables."
  value = {
    for key, variable in github_actions_environment_variable.this : key => {
      name = variable.variable_name
    }
  }
}
