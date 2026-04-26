output "variables" {
  description = "Managed Actions variables keyed by the input map key, each carrying its `name`."
  value = { for key, variable in github_actions_variable.this : key => {
    name = variable.variable_name
  } }
}
