output "exemptions" {
  description = "Map of exemption details keyed by the input map key."
  value = {
    for k, v in module.exemption : k => {
      name        = v.name
      resource_id = v.resource_id
      scope_kind  = v.scope_kind
    }
  }
}
