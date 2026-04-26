output "exemptions" {
  description = "Map of exemption details keyed by the input map key."
  value = {
    for k, v in module.exemption : k => {
      resource_id = v.resource_id
      name        = v.name
      scope_kind  = v.scope_kind
    }
  }
}
