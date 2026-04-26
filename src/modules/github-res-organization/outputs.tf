output "name" {
  description = "Login name of the organization."
  value       = data.github_organization.this.login
}

output "id" {
  description = "Numeric ID of the organization."
  value       = data.github_organization.this.id
}

output "node_id" {
  description = "GraphQL global node ID of the organization."
  value       = data.github_organization.this.node_id
}

output "variables" {
  description = "Map of organization Actions variables, keyed by variable name."
  value       = module.variables.variables
}

output "secrets" {
  description = "Map of organization Actions secret names (values are not exposed)."
  value       = module.secrets.secrets
}
