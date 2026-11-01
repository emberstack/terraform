variable "name" {
  type        = string
  description = "Name of the network settings resource."
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the network settings in. Mirrors AVM `resource_group_name`."
  nullable    = false

  validation {
    condition     = length(var.resource_group_name) > 0 && !startswith(var.resource_group_name, "/")
    error_message = "resource_group_name must be a name, not a resource ID."
  }
}

variable "location" {
  type        = string
  description = "Azure region of the network settings. Must be the region of the virtual network that holds `subnet_resource_id`."
  nullable    = false
}

variable "subnet_resource_id" {
  type        = string
  description = "Resource ID of the subnet GitHub-hosted runners are injected into. It must be delegated to `GitHub.Network/networkSettings`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualNetworks/[^/]+/subnets/[^/]+$", var.subnet_resource_id))
    error_message = "subnet_resource_id must be a subnet resource ID: /subscriptions/<id>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<vnet>/subnets/<subnet>."
  }
}

variable "business_id" {
  type        = string
  description = "Database ID of the GitHub enterprise or organization the runners belong to — the numeric `databaseId` from GitHub's GraphQL API, not its login or node ID."
  nullable    = false

  validation {
    condition     = can(regex("^[0-9]+$", var.business_id))
    error_message = "business_id must be the numeric GitHub database ID."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags to apply to the network settings. `GitHubId` is GitHub's own tag and is ignored here."
  nullable    = false
}
