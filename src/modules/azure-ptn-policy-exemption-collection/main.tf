# =============================================================================
# AZURE POLICY EXEMPTION COLLECTION
# =============================================================================
# Manages a map of Azure Policy exemptions through a single module call. Each
# entry composes one `azure-res-policy-exemption`, which handles the
# subscription / resource-group / resource / management-group scope routing.
#
# This is the right shape when a single deployment needs to declare many
# exemptions (compliance baselines, framework rollups, custom-role allowlists)
# without instantiating the resource module by hand for each one.
# =============================================================================

module "exemption" {
  source   = "../azure-res-policy-exemption"
  for_each = var.exemptions

  name                            = each.value.name
  scope                           = each.value.scope
  policy_assignment_id            = each.value.policy_assignment_id
  exemption_category              = each.value.exemption_category
  display_name                    = each.value.display_name
  description                     = each.value.description
  expires_on                      = each.value.expires_on
  policy_definition_reference_ids = each.value.policy_definition_reference_ids
  metadata                        = each.value.metadata
}
