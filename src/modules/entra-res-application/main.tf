# =============================================================================
# ENTRA ID APPLICATION
# =============================================================================
# An application registration and, by default, its service principal, plus the
# pieces that only mean something alongside them: a client secret, a claims
# mapping policy, a SAML token-signing certificate, and user and group
# assignments.
#
# Owners and user assignments can be passed as either Entra object IDs (UUIDs)
# or user principal names (UPNs). Auto-routed by format: UUID values are used
# directly, UPN values are resolved via the `azuread_user` data source (Graph
# lookup). Group assignments take object IDs only.
# =============================================================================

data "azuread_client_config" "current" {}

locals {
  uuid_pattern = "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$"

  # One lookup serves both objects, so a UPN that owns both is read once.
  owner_upns = toset([
    for v in concat(values(var.owners), values(var.service_principal.owners)) : v
    if !can(regex(local.uuid_pattern, v))
  ])

  application_owners = [
    for v in values(var.owners) :
    can(regex(local.uuid_pattern, v)) ? v : data.azuread_user.owners[v].object_id
  ]

  service_principal_owners = [
    for v in values(var.service_principal.owners) :
    can(regex(local.uuid_pattern, v)) ? v : data.azuread_user.owners[v].object_id
  ]

  user_assignments_by_upn = {
    for k, v in var.user_assignments : k => v if !can(regex(local.uuid_pattern, v))
  }
}

data "azuread_user" "owners" {
  for_each = local.owner_upns

  user_principal_name = each.value
}

# -----------------------------------------------------------------------------
# Application
# -----------------------------------------------------------------------------

resource "azuread_application" "this" {
  display_name     = var.display_name
  description      = var.description
  sign_in_audience = var.sign_in_audience
  owners           = local.application_owners
  tags             = var.tags
  identifier_uris  = var.identifier_uris

  dynamic "web" {
    for_each = var.web == null ? [] : [var.web]
    content {
      redirect_uris = web.value.redirect_uris
      logout_url    = web.value.logout_url

      dynamic "implicit_grant" {
        for_each = web.value.implicit_grant == null ? [] : [web.value.implicit_grant]
        content {
          id_token_issuance_enabled     = implicit_grant.value.id_token_issuance_enabled
          access_token_issuance_enabled = implicit_grant.value.access_token_issuance_enabled
        }
      }
    }
  }

  dynamic "required_resource_access" {
    for_each = var.api_permissions
    content {
      resource_app_id = required_resource_access.value.resource_app_id

      dynamic "resource_access" {
        for_each = required_resource_access.value.resource_access
        content {
          id   = resource_access.value.id
          type = resource_access.value.type
        }
      }
    }
  }

  dynamic "api" {
    for_each = var.api == null ? [] : [var.api]
    content {
      mapped_claims_enabled          = api.value.mapped_claims_enabled
      requested_access_token_version = api.value.requested_access_token_version
    }
  }
}

# -----------------------------------------------------------------------------
# Client secret
# -----------------------------------------------------------------------------

resource "azuread_application_password" "this" {
  count = var.password != null ? 1 : 0

  application_id = azuread_application.this.id
  display_name   = var.password.display_name
  end_date       = var.password.end_date
}

# -----------------------------------------------------------------------------
# Service principal
# -----------------------------------------------------------------------------

resource "azuread_service_principal" "this" {
  count = var.service_principal.enabled ? 1 : 0

  client_id                    = azuread_application.this.client_id
  app_role_assignment_required = var.service_principal.app_role_assignment_required
  owners                       = local.service_principal_owners

  # tags and feature_tags are mutually exclusive in the provider.
  tags = var.service_principal.feature_tags != null ? null : var.service_principal.tags

  dynamic "feature_tags" {
    for_each = var.service_principal.feature_tags == null ? [] : [var.service_principal.feature_tags]
    content {
      enterprise            = feature_tags.value.enterprise
      custom_single_sign_on = feature_tags.value.custom_single_sign_on
      gallery               = feature_tags.value.gallery
      hide                  = feature_tags.value.hide
    }
  }

  # Null for an OIDC app, which leaves the provider default alone.
  preferred_single_sign_on_mode = var.service_principal.saml != null ? "saml" : null
  login_url                     = try(var.service_principal.saml.login_url, null)
  notification_email_addresses  = try(var.service_principal.saml.notification_email_addresses, [])

  dynamic "saml_single_sign_on" {
    for_each = var.service_principal.saml == null ? [] : [var.service_principal.saml]
    content {
      relay_state = saml_single_sign_on.value.relay_state
    }
  }
}

# -----------------------------------------------------------------------------
# SAML token-signing certificate
# -----------------------------------------------------------------------------
# The certificate Entra signs assertions with. Without it the app has no
# federation metadata to hand the service provider, so a SAML app is not
# usable until this exists.

resource "azuread_service_principal_token_signing_certificate" "this" {
  count = var.service_principal.saml != null ? 1 : 0

  service_principal_id = azuread_service_principal.this[0].id
  display_name         = coalesce(var.service_principal.saml.certificate.display_name, "CN=${var.display_name}")
  end_date             = var.service_principal.saml.certificate.end_date
}

# -----------------------------------------------------------------------------
# Claims mapping policy
# -----------------------------------------------------------------------------
# The policy is a directory object in its own right, assigned to the service
# principal rather than the application. Creating one needs
# Policy.ReadWrite.ApplicationConfiguration (app-only auth) or Application
# Administrator (user auth) — a higher bar than the rest of this module.

resource "azuread_claims_mapping_policy" "this" {
  count = var.claims_mapping_policy != null ? 1 : 0

  display_name = var.claims_mapping_policy.display_name
  definition   = [var.claims_mapping_policy.definition]
}

resource "azuread_service_principal_claims_mapping_policy_assignment" "this" {
  count = var.claims_mapping_policy != null ? 1 : 0

  claims_mapping_policy_id = azuread_claims_mapping_policy.this[0].id
  service_principal_id     = azuread_service_principal.this[0].id
}

# -----------------------------------------------------------------------------
# Assignments
# -----------------------------------------------------------------------------
# Every assignment uses Default Access, the implicit role of an app that
# defines no app roles of its own.
#
# `for_each` is keyed on the input map itself, NOT on a regex-filtered copy of
# it, and the UUID-vs-UPN decision happens per entry in the body. The lookup
# below is still value-derived, so every user assignment value — UUID or UPN —
# must be known at plan time. Group assignments have no lookup and take object
# IDs that are only known after apply.

data "azuread_user" "assignments" {
  for_each = toset(values(local.user_assignments_by_upn))

  user_principal_name = each.value
}

resource "azuread_app_role_assignment" "users" {
  for_each = var.user_assignments

  app_role_id = "00000000-0000-0000-0000-000000000000"
  principal_object_id = (
    can(regex(local.uuid_pattern, each.value))
    ? each.value
    : data.azuread_user.assignments[each.value].object_id
  )
  resource_object_id = azuread_service_principal.this[0].object_id
}

resource "azuread_app_role_assignment" "groups" {
  for_each = var.group_assignments

  app_role_id         = "00000000-0000-0000-0000-000000000000"
  principal_object_id = each.value
  resource_object_id  = azuread_service_principal.this[0].object_id
}
