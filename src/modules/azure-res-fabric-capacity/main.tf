# =============================================================================
# AZURE FABRIC CAPACITY (Microsoft.Fabric/capacities)
# =============================================================================
# Mirrors the AVM `Azure/avm-res-fabric-capacity/azure` input shape (`name`,
# `location`, `tags`, `role_assignments`), over a `resource_group_name` rather
# than that module's `parent_id`, so call sites match the rest of this family.
#
# ARM stores `properties.administration.members` as an unordered set and returns
# it in an order of its own that a caller can neither predict nor set. Sending a
# sorted list — what AVM 0.1.0 does — diffs on every plan forever: the apply
# succeeds, ARM keeps its own order, and the next refresh renders the same
# reorder. Measured against two live capacities, on two subscriptions, where a
# PATCH carrying the sorted list left ARM's order untouched.
#
# The members path is therefore excluded from body comparison and reconciled by
# the imperative PATCH below, whose body is config-derived and never refreshed
# from ARM. Membership still converges; only its ordering stops being compared.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  provider_subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  resource_group_resource_id        = "${local.provider_subscription_resource_id}/resourceGroups/${var.resource_group_name}"

  # Sorted for a stable body: the value is never compared against ARM's ordering
  # (see the banner), so this only keeps the plan output and the reconciling
  # PATCH from churning when a caller reorders the input.
  administration_members = sort(tolist(var.administration_members))

  # Every role this module assigns, as the caller spelled it — a display name or an
  # ARM resource ID. Deduplication happens in `role_definition_resource_ids`.
  role_definition_names = [for v in values(var.role_assignments) : v.role_definition_id_or_name]

  role_definition_name_to_resource_id = length(local.role_definition_names) > 0 ? {
    for definition in data.azapi_resource_list.role_definitions[0].output.results : definition.role_name => definition.id
  } : {}

  # Keyed by role, not by assignment key: a role definition is a property of the
  # ROLE, so two assignments naming the same role share one entry. An entry that is
  # already a resource ID falls through the lookup untouched and maps to itself.
  role_definition_resource_ids = {
    for name in toset(local.role_definition_names) :
    name => lookup(local.role_definition_name_to_resource_id, name, name)
  }
}

# -----------------------------------------------------------------------------
# Fabric capacity
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Fabric/capacities@2023-11-01"
  body = {
    properties = {
      administration = {
        members = local.administration_members
      }
    }
    sku = {
      name = var.sku_name
      # The only tier the capacities API accepts. Exposing it would offer a
      # choice that does not exist.
      tier = "Fabric"
    }
  }
  # See the banner. Membership is reconciled by `azapi_resource_action` below;
  # without this every plan renders ARM's ordering as a change.
  ignore_body_changes = ["properties.administration.members"]
  # Only the read-only attributes exposed as outputs. Exporting the whole
  # response would persist the administration members and SKU for no benefit.
  response_export_values = {
    provisioning_state = "properties.provisioningState"
    state              = "properties.state"
  }
  tags = var.tags
}

# -----------------------------------------------------------------------------
# Administration members
# -----------------------------------------------------------------------------
# `ignore_body_changes` above stops the capacity from ever sending this path
# again after create, so membership needs an owner. An action's body is taken
# from configuration and never refreshed against ARM, which is what makes it
# order-stable where the resource's own body is not: it re-runs when the member
# set changes and stays quiet when it does not.

resource "azapi_resource_action" "administration_members" {
  method      = "PATCH"
  resource_id = azapi_resource.this.id
  type        = "Microsoft.Fabric/capacities@2023-11-01"
  body = {
    properties = {
      administration = {
        members = local.administration_members
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Role assignments
# -----------------------------------------------------------------------------

data "azapi_resource_list" "role_definitions" {
  count = length(local.role_definition_names) > 0 ? 1 : 0

  parent_id = local.provider_subscription_resource_id
  type      = "Microsoft.Authorization/roleDefinitions@2022-04-01"
  response_export_values = {
    results = "value[].{id: id, role_name: properties.roleName}"
  }
}

resource "random_uuid" "role_assignment_name" {
  for_each = var.role_assignments
}

resource "azapi_resource" "role_assignments" {
  for_each = var.role_assignments

  name      = coalesce(each.value.name, random_uuid.role_assignment_name[each.key].result)
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Authorization/roleAssignments@2022-04-01"
  body = {
    properties = {
      condition                          = each.value.condition
      conditionVersion                   = each.value.condition_version
      delegatedManagedIdentityResourceId = each.value.delegated_managed_identity_resource_id
      description                        = each.value.description
      principalId                        = each.value.principal_id
      principalType                      = each.value.principal_type
      roleDefinitionId                   = local.role_definition_resource_ids[each.value.role_definition_id_or_name]
    }
  }

  lifecycle {
    precondition {
      # An unresolved name falls through the `lookup` default in
      # `role_definition_resource_ids` and reaches ARM as a bare string in
      # `roleDefinitionId`, which fails with an error naming neither the role nor
      # this assignment. Every resolved value is an ARM ID, so it starts with "/".
      condition     = startswith(local.role_definition_resource_ids[each.value.role_definition_id_or_name], "/")
      error_message = <<-EOT
        role_assignments["${each.key}"] names the role "${each.value.role_definition_id_or_name}",
        which matched no role definition.

        Pass a role's display name exactly as Azure spells it, or a full
        role-definition resource ID. Names resolve against the roleDefinitions
        catalogue of the provider's subscription, so a CUSTOM role defined in a
        different subscription is not listed there and must be passed as an ID.
      EOT
    }
  }
}
