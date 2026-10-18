# =============================================================================
# ENTRA ID SERVICE PRINCIPAL
# =============================================================================
# A service principal for an application registered somewhere else — a
# Microsoft first-party application, or another tenant's multi-tenant one. The
# application object is not in this tenant, so there is nothing for
# `entra-res-application` to create; this module instantiates the tenant's
# copy of it and nothing more.
#
# `prevent_destroy` is hardcoded. A service a tenant depends on usually reaches
# it through exactly this object, and a replacement comes back with a new object
# ID, without its app role assignments or consents. Retiring one is a
# `terraform state rm` followed by a deliberate delete, not a destroy.
#
# Owners can be passed as either Entra object IDs (UUIDs) or user principal
# names (UPNs). Auto-routed by format: UUID values are used directly, UPN values
# are resolved via the `azuread_user` data source (Graph lookup).
# =============================================================================

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  owner_upns = toset([
    for v in values(var.owners) : v if !can(regex(local.uuid_pattern, v))
  ])

  owners = [
    for v in values(var.owners) :
    can(regex(local.uuid_pattern, v)) ? v : data.azuread_user.owners[v].object_id
  ]
}

data "azuread_user" "owners" {
  for_each = local.owner_upns

  user_principal_name = each.value
}

# -----------------------------------------------------------------------------
# Service principal
# -----------------------------------------------------------------------------

resource "azuread_service_principal" "this" {
  client_id                    = var.client_id
  account_enabled              = var.account_enabled
  app_role_assignment_required = var.app_role_assignment_required
  description                  = var.description
  notes                        = var.notes
  owners                       = local.owners
  use_existing                 = var.use_existing

  # Computed by the provider: null leaves whatever tags the service principal
  # already carries, which for a first-party application are Microsoft's.
  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}
