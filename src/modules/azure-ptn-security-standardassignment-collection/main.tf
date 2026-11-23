# =============================================================================
# DEFENDER FOR CLOUD RECOMMENDATION EXEMPTION COLLECTION
# =============================================================================
# Many Defender for Cloud recommendation exemptions from one map. Each entry
# composes one `azure-res-security-standardassignment`, which owns the scope
# routing and the GUID name derivation.
# =============================================================================

module "exemption" {
  source   = "../azure-res-security-standardassignment"
  for_each = var.exemptions

  scope                = each.value.scope
  assigned_standard_id = each.value.assigned_standard_id
  assessment_key       = each.value.assessment_key
  exemption_category   = each.value.exemption_category
  name                 = each.value.name
  display_name         = each.value.display_name
  description          = each.value.description
  expires_on           = each.value.expires_on
}
