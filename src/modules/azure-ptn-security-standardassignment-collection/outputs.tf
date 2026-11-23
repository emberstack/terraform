output "exemptions" {
  description = "Exemption details keyed by the input map key: `name`, `resource_id` and `scope_kind`."
  value = {
    for k, v in module.exemption : k => {
      name        = v.name
      resource_id = v.resource_id
      scope_kind  = v.scope_kind
    }
  }
}
