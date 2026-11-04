# =============================================================================
# azure-res-cdn-profile/modules/origin-group tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {}

variables {
  cdn_profile_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Cdn/profiles/afd-example"
  name                    = "og-example"
  origins = {
    web = {
      host_name = "stexample.z6.web.core.windows.net"
      private_link = {
        target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"
        group_id           = "web"
        location           = "westeurope"
      }
    }
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_a_private_link_static_website_origin" {
  command = plan

  assert {
    condition     = azapi_resource.this.body.properties.authentication == null
    error_message = "an origin group without authentication must send it as null"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.healthProbeSettings.probeProtocol == "Https" &&
      azapi_resource.this.body.properties.healthProbeSettings.probeRequestType == "HEAD" &&
      azapi_resource.this.body.properties.healthProbeSettings.probePath == "/" &&
      azapi_resource.this.body.properties.healthProbeSettings.probeIntervalInSeconds == 100
    )
    error_message = "the health probe must default to HTTPS HEAD / every 100 seconds"
  }
  assert {
    condition     = azapi_resource.this.body.properties.sessionAffinityState == "Disabled"
    error_message = "session affinity must default to off"
  }
  assert {
    condition     = azapi_resource.origin["web"].body.properties.originHostHeader == "stexample.z6.web.core.windows.net"
    error_message = "the origin host header must default to the host name"
  }
  assert {
    condition = (
      azapi_resource.origin["web"].body.properties.sharedPrivateLinkResource.groupId == "web" &&
      azapi_resource.origin["web"].body.properties.sharedPrivateLinkResource.privateLinkLocation == "westeurope" &&
      azapi_resource.origin["web"].body.properties.sharedPrivateLinkResource.privateLink.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"
    )
    error_message = "a private_link origin must send its shared private link resource"
  }
  assert {
    condition     = azapi_resource.origin["web"].body.properties.enforceCertificateNameCheck && azapi_resource.origin["web"].body.properties.httpsPort == 443
    error_message = "certificate name checks and port 443 must be the defaults"
  }
}

run "plans_a_managed_identity_blob_origin_without_a_probe" {
  command = plan

  variables {
    origins = {
      blob = {
        host_name = "stexample.blob.core.windows.net"
      }
    }
    authentication = {
      user_assigned_identity_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-afd"
    }
  }

  assert {
    condition = (
      azapi_resource.this.body.properties.authentication.type == "UserAssignedIdentity" &&
      azapi_resource.this.body.properties.authentication.scope == "https://storage.azure.com/.default" &&
      azapi_resource.this.body.properties.authentication.userAssignedIdentity.id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-afd"
    )
    error_message = "managed-identity authentication must send the identity and the storage scope"
  }
  assert {
    condition     = azapi_resource.origin["blob"].body.properties.sharedPrivateLinkResource == null
    error_message = "a public origin must send no shared private link resource"
  }
}

run "plans_a_single_origin_with_probing_disabled" {
  command = plan

  variables {
    health_probe = null
  }

  assert {
    condition     = azapi_resource.this.body.properties.healthProbeSettings == null
    error_message = "a disabled probe must be sent as null"
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_managed_identity_on_a_private_link_group" {
  command = plan

  variables {
    authentication = {
      type = "SystemAssignedIdentity"
    }
  }

  expect_failures = [var.authentication]
}

run "rejects_managed_identity_with_an_http_probe" {
  command = plan

  variables {
    origins = {
      blob = { host_name = "stexample.blob.core.windows.net" }
    }
    health_probe   = { protocol = "Http" }
    authentication = { type = "SystemAssignedIdentity" }
  }

  expect_failures = [var.authentication]
}

run "rejects_an_unsupported_token_scope" {
  command = plan

  variables {
    origins = {
      blob = { host_name = "stexample.blob.core.windows.net" }
    }
    authentication = {
      type  = "SystemAssignedIdentity"
      scope = "https://management.azure.com/.default"
    }
  }

  expect_failures = [var.authentication]
}

run "rejects_a_user_assigned_type_without_an_identity" {
  command = plan

  variables {
    origins = {
      blob = { host_name = "stexample.blob.core.windows.net" }
    }
    authentication = {}
  }

  expect_failures = [var.authentication]
}

run "rejects_mixing_public_and_private_link_origins" {
  command = plan

  variables {
    origins = {
      web = {
        host_name = "stexample.z6.web.core.windows.net"
        private_link = {
          target_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"
          group_id           = "web"
          location           = "westeurope"
        }
      }
      blob = { host_name = "stexample.blob.core.windows.net" }
    }
  }

  expect_failures = [var.origins]
}

run "rejects_disabled_probing_with_two_enabled_origins" {
  command = plan

  variables {
    origins = {
      one = { host_name = "one.example.com" }
      two = { host_name = "two.example.com" }
    }
    health_probe = null
  }

  expect_failures = [var.health_probe]
}

run "rejects_an_out_of_range_priority" {
  command = plan

  variables {
    origins = {
      one = {
        host_name = "one.example.com"
        priority  = 6
      }
    }
  }

  expect_failures = [var.origins]
}

run "rejects_more_successful_samples_than_samples" {
  command = plan

  variables {
    load_balancing = {
      sample_size                 = 2
      successful_samples_required = 3
    }
  }

  expect_failures = [var.load_balancing]
}
