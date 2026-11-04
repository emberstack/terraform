# =============================================================================
# FRONT DOOR ORIGIN GROUP (Microsoft.Cdn/profiles/originGroups)
# =============================================================================
# One origin group, and its origins, on an existing Front Door profile. The
# profile is usually shared while each origin group belongs to whoever owns the
# origin, so it is a unit of its own rather than an input on the profile.
#
# Origins reach their backend one of two ways, and an origin group cannot mix
# them:
#   - publicly, optionally authenticated with a managed identity of the profile
#     (`authentication`). Front Door fetches an Entra token for `scope` and sends
#     it as a bearer token on every request, health probes included.
#   - over Private Link (`private_link` on each origin, Premium only). Front Door
#     creates a private endpoint in a network it manages and the target's owner
#     has to approve the connection — out of band, since the connection lives on
#     the target, not here. Until it is approved the origin answers with errors.
#
# Managed-identity authentication is not supported on a Private Link origin, and
# needs an HTTPS health probe and routes that forward HTTPS only. The variables
# reject the combinations ARM documents as invalid.
#
# Properties that can be switched off (`authentication`, `healthProbeSettings`,
# `sharedPrivateLinkResource`) are sent as null rather than left out, so that
# turning one off is a change azapi can see.
# =============================================================================

locals {
  origin_group_properties = {
    authentication = var.authentication == null ? null : {
      scope = var.authentication.scope
      type  = var.authentication.type
      userAssignedIdentity = var.authentication.type == "UserAssignedIdentity" ? {
        id = var.authentication.user_assigned_identity_resource_id
      } : null
    }
    healthProbeSettings = var.health_probe == null ? null : {
      probeIntervalInSeconds = var.health_probe.interval_in_seconds
      probePath              = var.health_probe.path
      probeProtocol          = var.health_probe.protocol
      probeRequestType       = var.health_probe.request_type
    }
    loadBalancingSettings = {
      additionalLatencyInMilliseconds = var.load_balancing.additional_latency_in_milliseconds
      sampleSize                      = var.load_balancing.sample_size
      successfulSamplesRequired       = var.load_balancing.successful_samples_required
    }
    sessionAffinityState = var.session_affinity_enabled ? "Enabled" : "Disabled"
  }
}

# -----------------------------------------------------------------------------
# Origin group
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  name      = var.name
  parent_id = var.cdn_profile_resource_id
  type      = "Microsoft.Cdn/profiles/originGroups@2025-12-01"
  body = {
    properties = local.origin_group_properties
  }
}

# -----------------------------------------------------------------------------
# Origins
# -----------------------------------------------------------------------------
# The origin host header defaults to the host name: Blob Storage, static
# websites and App Service all reject a request whose Host does not name them.

resource "azapi_resource" "origin" {
  for_each = var.origins

  name      = each.key
  parent_id = azapi_resource.this.id
  type      = "Microsoft.Cdn/profiles/originGroups/origins@2025-12-01"
  body = {
    properties = {
      enabledState                = each.value.enabled ? "Enabled" : "Disabled"
      enforceCertificateNameCheck = each.value.certificate_name_check_enabled
      hostName                    = each.value.host_name
      httpPort                    = each.value.http_port
      httpsPort                   = each.value.https_port
      originHostHeader            = coalesce(each.value.origin_host_header, each.value.host_name)
      priority                    = each.value.priority
      sharedPrivateLinkResource = each.value.private_link == null ? null : {
        groupId = each.value.private_link.group_id
        privateLink = {
          id = each.value.private_link.target_resource_id
        }
        privateLinkLocation = each.value.private_link.location
        requestMessage      = each.value.private_link.request_message
      }
      weight = each.value.weight
    }
  }
}
