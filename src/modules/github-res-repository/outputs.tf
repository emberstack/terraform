output "name" {
  description = "Repository name."
  value       = github_repository.this.name
}

output "id" {
  description = "Numeric GitHub repository ID (`repo_id`). This is the REST API identifier — use `node_id` for GraphQL."
  value       = github_repository.this.repo_id
}

output "node_id" {
  description = "GraphQL global node ID for the repository."
  value       = github_repository.this.node_id
}

output "html_url" {
  description = "Browser URL of the repository."
  value       = github_repository.this.html_url
}

output "full_name" {
  description = "Fully qualified repository name in `owner/name` form."
  value       = github_repository.this.full_name
}

output "variables" {
  description = "Map of managed GitHub Actions variables, keyed by variable name."
  value       = module.variables.variables
}

output "rulesets" {
  description = "Map of managed repository rulesets, keyed by ruleset name."
  value       = module.rulesets.rulesets
}
