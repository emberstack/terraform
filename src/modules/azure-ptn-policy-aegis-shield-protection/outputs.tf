output "definition_id" {
  description = "ARM resource ID of the deny-delete-by-ID policy definition."
  value       = module.definition.resource_id
}

output "assignments" {
  description = "Map of assignment details keyed by the input map key."
  value = {
    for k, v in module.assignment : k => {
      resource_id = v.resource_id
      name        = v.name
      scope_kind  = v.scope_kind
    }
  }
}
