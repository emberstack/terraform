output "role_definitions" {
  description = "Map of role-definition details keyed by the input map key."
  value = {
    for k, v in module.role_definition : k => {
      resource_id        = v.resource_id
      role_definition_id = v.role_definition_id
      name               = v.name
      scope              = v.scope
    }
  }
}
