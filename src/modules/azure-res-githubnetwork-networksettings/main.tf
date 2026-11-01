# =============================================================================
# GITHUB NETWORK SETTINGS (GitHub.Network/networkSettings)
# =============================================================================
# Registers a subnet with GitHub so GitHub-hosted runners can be injected into
# it (Azure private networking). GitHub identifies the registration by the
# `GitHubId` tag it writes onto the resource after creation — the value an
# organization's or enterprise's hosted compute network configuration asks for.
#
# The subnet must already be delegated to `GitHub.Network/networkSettings`.
# Creating the resource puts a service association link on the subnet that
# blocks deleting or re-delegating the subnet while this resource exists.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider.
  resource_group_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"
}

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "GitHub.Network/networkSettings@2024-04-02"
  body = {
    properties = {
      businessId = var.business_id
      subnetId   = var.subnet_resource_id
    }
  }
  tags = var.tags

  lifecycle {
    # `GitHubId` is GitHub's, written after creation. Without the ignore every
    # plan would propose removing it; with it, every write carries the tag over
    # from state.
    ignore_changes = [tags["GitHubId"]]
  }
}
