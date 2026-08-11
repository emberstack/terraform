# =============================================================================
# AZURE POLICY DEFINITION (Microsoft.Authorization/policyDefinitions)
# =============================================================================
# A single custom Azure Policy definition. Scope is implicit:
#   - management_group_id set  -> scoped to that management group
#   - management_group_id null -> scoped to the current subscription
#
# `policy_rule`, `parameters` and `metadata` are sent as native objects. The
# azurerm resource required them JSON-encoded into strings; AzAPI does not, so
# the module no longer encodes on the caller's behalf.
#
# Azure injects `createdBy`/`createdOn`/`updatedBy`/`updatedOn` into `metadata`
# alongside whatever the caller sets. They are server-maintained and not sent.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  scope_resource_id = coalesce(
    var.management_group_id,
    "/subscriptions/${data.azapi_client_config.current.subscription_id}",
  )
}

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = local.scope_resource_id
  type      = "Microsoft.Authorization/policyDefinitions@2023-04-01"
  body = {
    properties = {
      description = var.description
      displayName = var.display_name
      metadata    = length(var.metadata) > 0 ? var.metadata : null
      mode        = var.mode
      parameters  = length(var.parameters) > 0 ? var.parameters : null
      policyRule  = var.policy_rule
      policyType  = "Custom"
    }
  }
  # `metadata` is null unless the caller sets it, and ARM never returns it empty:
  # it injects `createdBy`/`createdOn`/`updatedBy`/`updatedOn` (measured
  # 2026-08-10). Without this, a caller that omits `metadata` compares null
  # against that populated object and carries a diff that never converges.
  ignore_null_property = true
}
