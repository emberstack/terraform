output "resource_id" {
  description = "Resource ID of the origin group — what a route's `origin_group_resource_id` names."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the origin group."
  value       = azapi_resource.this.name
}

output "origins" {
  description = "Map of origins keyed by the input map key — `resource_id` and `name`."
  value = {
    for k, v in azapi_resource.origin : k => {
      resource_id = v.id
      name        = v.name
    }
  }
}
