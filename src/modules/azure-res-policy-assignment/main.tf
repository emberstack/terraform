# =============================================================================
# AZURE POLICY ASSIGNMENT
# =============================================================================
# A single policy or initiative assignment. Scope is detected from the `scope`
# input format and routed to the right resource type:
#
#   /providers/Microsoft.Management/managementGroups/<mg>          -> mgmt group
#   /subscriptions/<sub>                                            -> subscription
#   /subscriptions/<sub>/resourceGroups/<rg>                        -> resource group
#   /subscriptions/<sub>/resourceGroups/<rg>/providers/...          -> resource
#
# When a managed identity is enabled, optional `identity_role_assignments` will
# grant the system-assigned identity the roles required for DeployIfNotExists /
# Modify policies — at the assignment scope by default, or at any scope you
# specify (commonly used to grant identity rights on a different resource group
# or subscription that the policy will remediate into).
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

  # Identity assembly
  has_user_assigned   = length(var.managed_identities.user_assigned_resource_ids) > 0
  has_system_assigned = var.managed_identities.system_assigned
  identity_type = (
    local.has_system_assigned && local.has_user_assigned ? "SystemAssigned, UserAssigned" :
    local.has_system_assigned ? "SystemAssigned" :
    local.has_user_assigned ? "UserAssigned" :
    null
  )

  is_subscription     = local.scope_kind == "subscription"
  is_resource_group   = local.scope_kind == "resource_group"
  is_resource         = local.scope_kind == "resource"
  is_management_group = local.scope_kind == "management_group"

  # The four assignment resources are mutually exclusive — pull the non-null
  # one through `coalesce` so downstream code can treat them uniformly.
  assignment_id = coalesce(
    try(one(values(azurerm_subscription_policy_assignment.this)).id, null),
    try(one(values(azurerm_resource_group_policy_assignment.this)).id, null),
    try(one(values(azurerm_resource_policy_assignment.this)).id, null),
    try(one(values(azurerm_management_group_policy_assignment.this)).id, null),
  )
  assignment_name = coalesce(
    try(one(values(azurerm_subscription_policy_assignment.this)).name, null),
    try(one(values(azurerm_resource_group_policy_assignment.this)).name, null),
    try(one(values(azurerm_resource_policy_assignment.this)).name, null),
    try(one(values(azurerm_management_group_policy_assignment.this)).name, null),
  )
  system_identity_principal_id = local.has_system_assigned ? coalesce(
    try(one(values(azurerm_subscription_policy_assignment.this)).identity[0].principal_id, null),
    try(one(values(azurerm_resource_group_policy_assignment.this)).identity[0].principal_id, null),
    try(one(values(azurerm_resource_policy_assignment.this)).identity[0].principal_id, null),
    try(one(values(azurerm_management_group_policy_assignment.this)).identity[0].principal_id, null),
  ) : null
}

# -----------------------------------------------------------------------------
# Subscription scope
# -----------------------------------------------------------------------------

resource "azurerm_subscription_policy_assignment" "this" {
  for_each = local.is_subscription ? toset([var.name]) : toset([])

  name                 = each.key
  subscription_id      = var.scope
  policy_definition_id = var.policy_definition_id
  display_name         = var.display_name
  description          = var.description
  enforce              = var.enforce
  location             = var.location
  not_scopes           = var.not_scopes
  metadata             = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
  parameters           = length(var.parameters) > 0 ? jsonencode(var.parameters) : null

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = local.has_user_assigned ? var.managed_identities.user_assigned_resource_ids : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = resource_selectors.key
      dynamic "selectors" {
        for_each = resource_selectors.value
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Resource group scope
# -----------------------------------------------------------------------------

resource "azurerm_resource_group_policy_assignment" "this" {
  for_each = local.is_resource_group ? toset([var.name]) : toset([])

  name                 = each.key
  resource_group_id    = var.scope
  policy_definition_id = var.policy_definition_id
  display_name         = var.display_name
  description          = var.description
  enforce              = var.enforce
  location             = var.location
  not_scopes           = var.not_scopes
  metadata             = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
  parameters           = length(var.parameters) > 0 ? jsonencode(var.parameters) : null

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = local.has_user_assigned ? var.managed_identities.user_assigned_resource_ids : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = resource_selectors.key
      dynamic "selectors" {
        for_each = resource_selectors.value
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Resource scope
# -----------------------------------------------------------------------------

resource "azurerm_resource_policy_assignment" "this" {
  for_each = local.is_resource ? toset([var.name]) : toset([])

  name                 = each.key
  resource_id          = var.scope
  policy_definition_id = var.policy_definition_id
  display_name         = var.display_name
  description          = var.description
  enforce              = var.enforce
  location             = var.location
  not_scopes           = var.not_scopes
  metadata             = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
  parameters           = length(var.parameters) > 0 ? jsonencode(var.parameters) : null

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = local.has_user_assigned ? var.managed_identities.user_assigned_resource_ids : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = resource_selectors.key
      dynamic "selectors" {
        for_each = resource_selectors.value
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Management group scope
# -----------------------------------------------------------------------------

resource "azurerm_management_group_policy_assignment" "this" {
  for_each = local.is_management_group ? toset([var.name]) : toset([])

  name                 = each.key
  management_group_id  = var.scope
  policy_definition_id = var.policy_definition_id
  display_name         = var.display_name
  description          = var.description
  enforce              = var.enforce
  location             = var.location
  not_scopes           = var.not_scopes
  metadata             = length(var.metadata) > 0 ? jsonencode(var.metadata) : null
  parameters           = length(var.parameters) > 0 ? jsonencode(var.parameters) : null

  dynamic "identity" {
    for_each = local.identity_type == null ? [] : [local.identity_type]
    content {
      type         = identity.value
      identity_ids = local.has_user_assigned ? var.managed_identities.user_assigned_resource_ids : null
    }
  }

  dynamic "non_compliance_message" {
    for_each = var.non_compliance_messages
    content {
      content                        = non_compliance_message.value.content
      policy_definition_reference_id = non_compliance_message.value.policy_definition_reference_id
    }
  }

  dynamic "overrides" {
    for_each = var.overrides
    content {
      value = overrides.value.value
      dynamic "selectors" {
        for_each = overrides.value.selectors
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }

  dynamic "resource_selectors" {
    for_each = var.resource_selectors
    content {
      name = resource_selectors.key
      dynamic "selectors" {
        for_each = resource_selectors.value
        content {
          kind   = selectors.value.kind
          in     = selectors.value.in
          not_in = selectors.value.not_in
        }
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Identity role assignments (for DeployIfNotExists / Modify remediation)
# -----------------------------------------------------------------------------
# Granted to the system-assigned identity. If only a user-assigned identity is
# attached, the caller is expected to manage role assignments on the UAI itself
# (since they outlive any single policy assignment).
# -----------------------------------------------------------------------------

resource "azurerm_role_assignment" "identity" {
  for_each = local.has_system_assigned ? var.identity_role_assignments : {}

  scope                                  = coalesce(each.value.scope, var.scope)
  principal_id                           = local.system_identity_principal_id
  role_definition_name                   = startswith(each.value.role_definition_id_or_name, "/") ? null : each.value.role_definition_id_or_name
  role_definition_id                     = startswith(each.value.role_definition_id_or_name, "/") ? each.value.role_definition_id_or_name : null
  description                            = each.value.description
  skip_service_principal_aad_check       = each.value.skip_service_principal_aad_check
  condition                              = each.value.condition
  condition_version                      = each.value.condition_version
  delegated_managed_identity_resource_id = each.value.delegated_managed_identity_resource_id
  principal_type                         = "ServicePrincipal"
}

# -----------------------------------------------------------------------------
# Validation
# -----------------------------------------------------------------------------

resource "terraform_data" "scope_validation" {
  lifecycle {
    precondition {
      condition     = local.scope_kind != "invalid"
      error_message = "scope must be a management group, subscription, resource group, or resource ARM resource ID."
    }
  }
}
