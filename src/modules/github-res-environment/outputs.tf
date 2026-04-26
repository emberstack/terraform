output "name" {
  description = "The environment name."
  value       = github_repository_environment.this.environment
}

output "id" {
  description = "The environment ID."
  value       = github_repository_environment.this.id
}

output "variables" {
  description = "The environment variables."
  value       = module.variables.variables
}
