# =============================================================================
# AZURE CUSTOM ROLE DEFINITION (Microsoft.Authorization/roleDefinitions)
# =============================================================================
# A single custom RBAC role definition. Anchored to one scope (typically a
# management group at or above the assignments) and assignable at one or more
# `assignable_scopes`. When `assignable_scopes` is omitted it defaults to the
# definition's own scope.
#
# The scope is the resource's `parent_id`, so one resource covers management
# group and subscription anchoring alike — azurerm needed no such split here,
# but its policy siblings did.
#
# `createdBy`/`createdOn`/`updatedBy`/`updatedOn` are server-maintained audit
# fields and deliberately not sent.
# =============================================================================

# ARM identifies the role by a GUID name. Azure generates one on create, so a
# caller that has not pinned `role_definition_id` gets a stable random one here
# rather than letting the name churn.
resource "random_uuid" "this" {}

resource "azapi_resource" "this" {
  name      = coalesce(var.role_definition_id, random_uuid.this.result)
  parent_id = var.scope
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  body = {
    properties = {
      assignableScopes = length(var.assignable_scopes) > 0 ? sort(tolist(var.assignable_scopes)) : [var.scope]
      description      = var.description
      permissions = [{
        actions        = sort(tolist(var.actions))
        dataActions    = sort(tolist(var.data_actions))
        notActions     = sort(tolist(var.not_actions))
        notDataActions = sort(tolist(var.not_data_actions))
      }]
      roleName = var.name
      type     = "CustomRole"
    }
  }
}
