# =============================================================================
# AZURE POLICY EXEMPTION
# =============================================================================
# A single policy exemption. Like assignments, exemptions are scope-bound and
# the resource type depends on the scope:
#
#   /providers/Microsoft.Management/managementGroups/<mg>          -> mgmt group
#   /subscriptions/<sub>                                            -> subscription
#   /subscriptions/<sub>/resourceGroups/<rg>                        -> resource group
#   /subscriptions/<sub>/resourceGroups/<rg>/providers/...          -> resource
# =============================================================================

locals {
  scope_kind = (
    startswith(var.scope, "/providers/Microsoft.Management/managementGroups/") ? "management_group" :
    can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", var.scope)) ? "resource" :
    can(regex("^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ? "resource_group" :
    can(regex("^/subscriptions/[^/]+/providers/", var.scope)) ? "resource" :
    can(regex("^/subscriptions/[^/]+$", var.scope)) ? "subscription" :
    "invalid"
  )

  is_subscription     = local.scope_kind == "subscription"
  is_resource_group   = local.scope_kind == "resource_group"
  is_resource         = local.scope_kind == "resource"
  is_management_group = local.scope_kind == "management_group"

  exemption_id = coalesce(
    try(one(values(azurerm_subscription_policy_exemption.this)).id, null),
    try(one(values(azurerm_resource_group_policy_exemption.this)).id, null),
    try(one(values(azurerm_resource_policy_exemption.this)).id, null),
    try(one(values(azurerm_management_group_policy_exemption.this)).id, null),
  )
}

resource "azurerm_subscription_policy_exemption" "this" {
  for_each = local.is_subscription ? toset([var.name]) : toset([])

  name                            = each.key
  subscription_id                 = var.scope
  policy_assignment_id            = var.policy_assignment_id
  exemption_category              = var.exemption_category
  display_name                    = var.display_name
  description                     = var.description
  expires_on                      = var.expires_on
  policy_definition_reference_ids = var.policy_definition_reference_ids
  metadata                        = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
}

resource "azurerm_resource_group_policy_exemption" "this" {
  for_each = local.is_resource_group ? toset([var.name]) : toset([])

  name                            = each.key
  resource_group_id               = var.scope
  policy_assignment_id            = var.policy_assignment_id
  exemption_category              = var.exemption_category
  display_name                    = var.display_name
  description                     = var.description
  expires_on                      = var.expires_on
  policy_definition_reference_ids = var.policy_definition_reference_ids
  metadata                        = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
}

resource "azurerm_resource_policy_exemption" "this" {
  for_each = local.is_resource ? toset([var.name]) : toset([])

  name                            = each.key
  resource_id                     = var.scope
  policy_assignment_id            = var.policy_assignment_id
  exemption_category              = var.exemption_category
  display_name                    = var.display_name
  description                     = var.description
  expires_on                      = var.expires_on
  policy_definition_reference_ids = var.policy_definition_reference_ids
  metadata                        = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
}

resource "azurerm_management_group_policy_exemption" "this" {
  for_each = local.is_management_group ? toset([var.name]) : toset([])

  name                            = each.key
  management_group_id             = var.scope
  policy_assignment_id            = var.policy_assignment_id
  exemption_category              = var.exemption_category
  display_name                    = var.display_name
  description                     = var.description
  expires_on                      = var.expires_on
  policy_definition_reference_ids = var.policy_definition_reference_ids
  metadata                        = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
}

resource "terraform_data" "scope_validation" {
  lifecycle {
    precondition {
      condition     = local.scope_kind != "invalid"
      error_message = "scope must be a management group, subscription, resource group, or resource ARM resource ID."
    }
  }
}
