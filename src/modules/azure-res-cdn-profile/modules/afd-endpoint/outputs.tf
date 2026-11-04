output "resource_id" {
  description = "Resource ID of the endpoint. Also the domain ID a security policy names for the endpoint's own hostname."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the endpoint."
  value       = azapi_resource.this.name
}

output "host_name" {
  description = "The endpoint's generated hostname, `<name>-<hash>.<zone>.azurefd.net`."
  value       = try(azapi_resource.this.output.host_name, null)
}

output "routes" {
  description = "Map of routes keyed by the input map key — `resource_id`, `name`, and `cache_rule_set_resource_id` (null without `cache.duration`)."
  value = {
    for k, v in azapi_resource.route : k => {
      resource_id                = v.id
      name                       = v.name
      cache_rule_set_resource_id = try(azapi_resource.cache_rule_set[k].id, null)
    }
  }
}

output "security_policy_resource_id" {
  description = "Resource ID of the security policy. Null when `security_policy` is not set."
  value       = try(azapi_resource.security_policy[0].id, null)
}
