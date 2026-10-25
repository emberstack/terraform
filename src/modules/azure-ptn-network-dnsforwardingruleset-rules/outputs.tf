output "rules" {
  description = "Map of created forwarding rules, keyed by the input map key. Each entry exposes `resource_id`, `name` and `domain_name`."
  value = {
    for k, v in azapi_resource.this : k => {
      resource_id = v.id
      name        = v.name
      domain_name = var.rules[k].domain_name
    }
  }
}

output "dns_forwarding_ruleset_resource_id" {
  description = "ARM resource ID of the ruleset the rules were written into, as supplied."
  value       = var.dns_forwarding_ruleset_resource_id
}
