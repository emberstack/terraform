# =============================================================================
# DEFENDER FOR CLOUD RECOMMENDATION EXEMPTION (Microsoft.Security/standardAssignments)
# =============================================================================
# A standard assignment with the `Exempt` effect for one Defender for Cloud
# recommendation (an assessment key) at one scope. It is meant for
# recommendations with no Azure Policy definition behind them, which
# `azure-res-policy-exemption` cannot reach. For a recommendation that IS
# backed by a policy, exempt the policy instead.
#
# Only `Exempt` is modelled. `Audit` assigns a whole standard, and `Attest`
# carries attestation evidence rather than exemption data; an `effect` input
# can be added later without breaking this interface.
#
# The scope is simply the resource's `parent_id`, exactly as in
# `azure-res-policy-exemption`: management group, subscription, resource group
# or resource.
#
# ARM requires the name to be a GUID. Left null, it is derived from the scope,
# standard and assessment key (lower-cased, since ARM IDs are
# case-insensitive), so the same exemption always gets the same name. Pass an
# explicit `name` to adopt an exemption created elsewhere, such as in the
# portal, by `terraform import`.
#
# Nothing here sets `response_export_values` or `ignore_null_property`: a change
# to either alone is a PUT, so adopting an existing exemption by import would
# cost a write. Unset optional fields are left out of the body instead.
# =============================================================================

locals {
  name = coalesce(var.name, uuidv5("url", join("|", [
    lower(var.scope),
    lower(var.assigned_standard_id),
    lower(var.assessment_key),
  ])))

  optional_properties = {
    description = var.description
    displayName = var.display_name
    expiresOn   = var.expires_on
  }

  # Feeds the `scope_kind` output only — the same detection, and the same
  # case folding, as `azure-res-policy-exemption`.
  scope_kind = (
    can(regex("(?i)^/providers/Microsoft\\.Management/managementGroups/", var.scope)) ? "management_group" :
    can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/", var.scope)) ? "resource" :
    can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+$", var.scope)) ? "resource_group" :
    can(regex("(?i)^/subscriptions/[^/]+/providers/", var.scope)) ? "resource" :
    "subscription"
  )
}

resource "azapi_resource" "this" {
  name      = local.name
  parent_id = var.scope
  type      = "Microsoft.Security/standardAssignments@2024-08-01"
  body = {
    properties = merge(
      {
        assignedStandard = {
          id = var.assigned_standard_id
        }
        effect = "Exempt"
        exemptionData = {
          assignedAssessment = {
            assessmentKey = var.assessment_key
          }
          exemptionCategory = var.exemption_category
        }
      },
      [for key, value in local.optional_properties : { (key) = value } if value != null]...
    )
  }
}
