# =============================================================================
# AZURE POLICY EXEMPTION (Microsoft.Authorization/policyExemptions)
# =============================================================================
# A single policy exemption at any scope. The scope is simply the resource's
# `parent_id`, so one resource covers all four:
#
#   /providers/Microsoft.Management/managementGroups/<mg>   -> management group
#   /subscriptions/<sub>                                    -> subscription
#   /subscriptions/<sub>/resourceGroups/<rg>                -> resource group
#   /subscriptions/<sub>/resourceGroups/<rg>/providers/...  -> resource
#
# The azurerm provider needed a distinct resource type per scope and a
# `terraform_data` precondition to police the routing; both are gone. Scope
# shape is now checked by a variable validation instead.
#
# `policyExemptions` has never shipped a stable API version. 2022-07-01-preview
# is pinned deliberately — it is the version these exemptions were created with,
# and a newer preview buys nothing here.
# =============================================================================

locals {
  # Kept only to preserve the `scope_kind` output; the resource itself no longer
  # branches on it, since the scope is just `parent_id`.
  #
  # Every matcher folds case (`(?i)`) because ARM ID segment names are
  # case-insensitive: `resourceGroups` can arrive as `RESOURCEGROUPS` and Azure
  # accepts it. The `scope` validation folds case identically, so casing alone can
  # never change which branch a scope lands on. The trailing `subscription` is the
  # answer for a plain `/subscriptions/<id>`, not an error path.
  scope_kind = (
    can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope)) ? "management_group" :
    can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", var.scope)) ? "resource" :
    can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ? "resource_group" :
    can(regex("(?i)^/subscriptions/[^/]+/providers/", var.scope)) ? "resource" :
    "subscription"
  )
}

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = var.scope
  type      = "Microsoft.Authorization/policyExemptions@2022-07-01-preview"
  body = {
    properties = {
      description                  = var.description
      displayName                  = var.display_name
      exemptionCategory            = var.exemption_category
      expiresOn                    = var.expires_on
      metadata                     = length(var.metadata) > 0 ? var.metadata : null
      policyAssignmentId           = var.policy_assignment_id
      policyDefinitionReferenceIds = sort(tolist(coalesce(var.policy_definition_reference_ids, [])))
    }
  }
  # `expiresOn` and `metadata` are null unless the caller sets them; ARM either
  # omits them or fills them in, and without this that null reads as "clear it".
  ignore_null_property = true
}
