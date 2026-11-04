output "resource_id" {
  description = "Resource ID of the rule set — what a route's `rule_set_resource_ids` lists. Depends on every rule, so a route that references it is written only once the rules exist."
  value       = azapi_resource.this.id

  depends_on = [azapi_resource.rule]
}

output "name" {
  description = "Name of the rule set."
  value       = azapi_resource.this.name
}

output "rules" {
  description = "Map of rules keyed by the input map key — `resource_id` and `name`."
  value = {
    for k, v in azapi_resource.rule : k => {
      resource_id = v.id
      name        = v.name
    }
  }
}
