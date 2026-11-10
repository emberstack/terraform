output "alert_rules" {
  description = "Map of created analytics rules, keyed by the input map key. Each entry exposes `resource_id`, `name` and `display_name`."
  value = {
    for k, v in azapi_resource.this : k => {
      resource_id  = v.id
      name         = v.name
      display_name = var.alert_rules[k].display_name
    }
  }
}

output "log_analytics_workspace_resource_id" {
  description = "ARM resource ID of the workspace the rules were written into, as supplied."
  value       = var.log_analytics_workspace_resource_id
}
