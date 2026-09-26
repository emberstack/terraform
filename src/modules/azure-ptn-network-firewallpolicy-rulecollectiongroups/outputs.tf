output "groups" {
  description = "Map of rule collection groups keyed by the input map key: `resource_id`, `name` and `priority`."
  value = {
    for key, group in azapi_resource.this : key => {
      resource_id = group.id
      name        = group.name
      priority    = var.groups[key].priority
    }
  }
}
