output "resource_id" {
  description = "Resource ID of the network settings."
  value       = azapi_resource.this.id
}

output "name" {
  description = "Name of the network settings."
  value       = azapi_resource.this.name
}

output "github_id" {
  description = <<-EOT
    The `GitHubId` GitHub assigned to this registration — what a hosted compute network
    configuration in GitHub asks for.

    GitHub writes it as a tag after creation and it is read at refresh, so it is null in
    the plan that creates the resource and set from the next refresh on.
  EOT
  value       = try(azapi_resource.this.tags["GitHubId"], null)
}
