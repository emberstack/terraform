# =============================================================================
# azure-res-aad-domainservice tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation or on a resource precondition, and the positive runs need a
# resource graph but not a real subscription. The region catalogue is mocked
# with the two regions the runs use.
#
# The positive runs are the ones that construct the resource graph and evaluate
# the outputs — an `expect_failures`-only suite never does, so a bad attribute
# reference would pass it green.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }

  mock_data "azapi_resource_list" {
    defaults = {
      output = {
        results = [
          {
            id        = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/acdd72a7-3385-48ef-bd42-f606fba81ae7"
            role_name = "Reader"
          },
        ]
      }
    }
  }

  mock_data "azapi_resource_action" {
    defaults = {
      output = {
        locations = [
          { name = "westeurope", display_name = "West Europe" },
          { name = "northeurope", display_name = "North Europe" },
        ]
      }
    }
  }
}

mock_provider "random" {}

variables {
  domain_name         = "aaddscontoso.com"
  resource_group_name = "rg-example"
  location            = "westeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-domain-services"
  sku                 = "Standard"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_minimal_domain_with_secure_defaults" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the managed domain must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = azapi_resource.this.name == "aaddscontoso.com"
    error_message = "name must default to domain_name"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.replicaSets) == 1 && azapi_resource.this.body.properties.replicaSets[0].location == "West Europe" && azapi_resource.this.body.properties.replicaSets[0].subnetId == var.subnet_resource_id
    error_message = "the initial replica set must be built from location and subnet_resource_id, its region sent as the display name ARM echoes"
  }
  assert {
    condition     = azapi_resource.this.location == "westeurope"
    error_message = "the resource's own location must keep the input spelling"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.domainSecuritySettings.ntlmV1 == "Disabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.tlsV1 == "Disabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.kerberosRc4Encryption == "Disabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.kerberosArmoring == "Enabled"
    )
    error_message = "the legacy protocols must be sent disabled and armoring enabled by default — the REST defaults are the permissive ones"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.domainSecuritySettings.syncNtlmPasswords == "Enabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.syncKerberosPasswords == "Enabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.syncOnPremPasswords == "Enabled"
    )
    error_message = "password hash sync must default on, or nobody can sign in"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.domainSecuritySettings) == 10
    error_message = "every security setting must be sent — a full-replace write resets anything left out"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ldapsSettings.ldaps == "Disabled" && azapi_resource.this.body.properties.ldapsSettings.externalAccess == "Disabled"
    error_message = "without secure_ldap, LDAPS must be sent explicitly disabled"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ldapsSettings.pfxCertificate == null && azapi_resource.this.ignore_null_property == true
    error_message = "without secure_ldap the certificate must be null, and dropped from the request by ignore_null_property"
  }
  assert {
    condition     = azapi_resource.this.body.properties.filteredSync == "Disabled" && azapi_resource.this.body.properties.syncScope == "All"
    error_message = "the whole directory must sync by default"
  }
  assert {
    condition     = azapi_resource.this.body.properties.domainConfigurationType == "FullySynced" && azapi_resource.this.body.properties.sku == "Standard"
    error_message = "configuration type and SKU must be sent"
  }
  assert {
    condition     = azapi_resource.this.body.properties.notificationSettings.notifyDcAdmins == "Enabled" && azapi_resource.this.body.properties.notificationSettings.notifyGlobalAdmins == "Enabled"
    error_message = "both admin notifications must default on"
  }
  assert {
    condition     = output.secure_ldap == null
    error_message = "the secure_ldap output must be null when secure LDAP is off"
  }
  assert {
    condition     = length(output.replica_sets) == 1 && output.replica_sets[0].subnet_resource_id == var.subnet_resource_id
    error_message = "the replica_sets output must evaluate — this is the run that catches bad attribute references"
  }
  assert {
    condition     = length(azapi_resource.lock) == 0 && length(azapi_resource.role_assignments) == 0 && length(azapi_resource.diagnostic_settings) == 0
    error_message = "no children unless asked for"
  }
}

run "plans_enterprise_domain_with_everything" {
  command = plan

  variables {
    name                  = "ds-example"
    sku                   = "Enterprise"
    filtered_sync_enabled = true
    sync_scope            = "CloudOnly"
    replica_sets = [
      {
        location           = "northeurope"
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example-neu/subnets/snet-domain-services"
      },
    ]
    security = {
      kerberos_rc4_encryption_enabled = true
      ldap_signing_enabled            = true
      sync_on_prem_passwords          = false
    }
    notifications = {
      notify_global_admins  = false
      additional_recipients = ["ops@example.com"]
    }
    secure_ldap = {
      external_access_enabled = true
    }
    secure_ldap_certificate = {
      pfx_certificate          = "TUlJRFBEQ0NBaVNnQXdJQkFnSVE="
      pfx_certificate_password = "example-password"
    }
    diagnostic_settings = {
      workspace = {
        workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
      }
    }
    role_assignments = {
      reader = {
        role_definition_id_or_name = "Reader"
        principal_id               = "11111111-1111-1111-1111-111111111111"
        principal_type             = "Group"
      }
    }
    lock = {
      kind = "CanNotDelete"
    }
  }

  assert {
    condition     = azapi_resource.this.name == "ds-example" && azapi_resource.this.body.properties.domainName == "aaddscontoso.com"
    error_message = "an explicit name must override the resource name and leave domain_name alone"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.replicaSets) == 2 && azapi_resource.this.body.properties.replicaSets[0].location == "West Europe" && azapi_resource.this.body.properties.replicaSets[1].location == "North Europe"
    error_message = "additional replica sets must follow the initial one, in input order"
  }
  assert {
    condition = (
      azapi_resource.this.body.properties.domainSecuritySettings.kerberosRc4Encryption == "Enabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.ldapSigning == "Enabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.syncOnPremPasswords == "Disabled" &&
      azapi_resource.this.body.properties.domainSecuritySettings.ntlmV1 == "Disabled"
    )
    error_message = "overridden security settings must be sent as configured, the rest at their defaults"
  }
  assert {
    condition     = azapi_resource.this.body.properties.filteredSync == "Enabled" && azapi_resource.this.body.properties.syncScope == "CloudOnly"
    error_message = "sync scoping must be sent as configured"
  }
  assert {
    condition     = azapi_resource.this.body.properties.ldapsSettings.ldaps == "Enabled" && azapi_resource.this.body.properties.ldapsSettings.externalAccess == "Enabled"
    error_message = "secure LDAP and external access must be sent enabled"
  }
  assert {
    condition     = nonsensitive(azapi_resource.this.body.properties.ldapsSettings.pfxCertificate == "TUlJRFBEQ0NBaVNnQXdJQkFnSVE=")
    error_message = "the certificate must travel in the body"
  }
  assert {
    condition     = azapi_resource.this.body.properties.notificationSettings.notifyGlobalAdmins == "Disabled" && azapi_resource.this.body.properties.notificationSettings.additionalRecipients[0] == "ops@example.com"
    error_message = "notification settings must be sent as configured"
  }
  assert {
    condition     = length(output.replica_sets) == 2 && output.replica_sets[1].location == "northeurope"
    error_message = "the replica_sets output must list the initial replica set first, then the additional ones"
  }
  assert {
    condition     = output.secure_ldap != null
    error_message = "the secure_ldap output must be an object when secure LDAP is on"
  }
  assert {
    condition     = azapi_resource.lock[0].name == "lock-ds-example" && azapi_resource.lock[0].body.properties.level == "CanNotDelete"
    error_message = "the lock must default its name from the resource name"
  }
  assert {
    condition     = startswith(azapi_resource.role_assignments["reader"].body.properties.roleDefinitionId, "/subscriptions/")
    error_message = "a role display name must resolve to a role definition ID"
  }
  assert {
    condition     = azapi_resource.diagnostic_settings["workspace"].body.properties.logs[0].categoryGroup == "allLogs" && azapi_resource.diagnostic_settings["workspace"].body.properties.metrics[0].category == "AllMetrics"
    error_message = "diagnostic settings must default to allLogs and AllMetrics"
  }
}

run "plans_display_name_region_unchanged" {
  command = plan

  variables {
    location = "West Europe"
  }

  assert {
    condition     = azapi_resource.this.body.properties.replicaSets[0].location == "West Europe"
    error_message = "a region passed as its display name must be sent as that display name"
  }
}

# =============================================================================
# NEGATIVE — validation must reject before anything reaches ARM
# =============================================================================

run "rejects_region_missing_from_catalogue" {
  command = plan

  variables {
    location = "atlantis"
  }

  expect_failures = [azapi_resource.this]
}

run "rejects_netbios_prefix_over_15_characters" {
  command = plan

  variables {
    domain_name = "aaddscontosolong.com"
  }

  expect_failures = [var.domain_name]
}

run "rejects_invalid_domain_name" {
  command = plan

  variables {
    domain_name = "-contoso.com"
  }

  expect_failures = [var.domain_name]
}

run "rejects_unknown_sku" {
  command = plan

  variables {
    sku = "Basic"
  }

  expect_failures = [var.sku]
}

run "rejects_gateway_subnet" {
  command = plan

  variables {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/GatewaySubnet"
  }

  expect_failures = [var.subnet_resource_id]
}

run "rejects_replica_set_on_standard_sku" {
  command = plan

  variables {
    replica_sets = [
      {
        location           = "northeurope"
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example-neu/subnets/snet-domain-services"
      },
    ]
  }

  expect_failures = [var.replica_sets]
}

run "rejects_replica_set_in_the_primary_region" {
  command = plan

  variables {
    sku = "Enterprise"
    replica_sets = [
      {
        location           = "West Europe"
        subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example-2/subnets/snet-domain-services"
      },
    ]
  }

  expect_failures = [var.replica_sets]
}

run "rejects_secure_ldap_without_certificate" {
  command = plan

  variables {
    secure_ldap = {}
  }

  expect_failures = [var.secure_ldap_certificate]
}

run "rejects_certificate_without_secure_ldap" {
  command = plan

  variables {
    secure_ldap_certificate = {
      pfx_certificate          = "TUlJRFBEQ0NBaVNnQXdJQkFnSVE="
      pfx_certificate_password = "example-password"
    }
  }

  expect_failures = [var.secure_ldap_certificate]
}

run "rejects_invalid_notification_recipient" {
  command = plan

  variables {
    notifications = {
      additional_recipients = ["not-an-address"]
    }
  }

  expect_failures = [var.notifications]
}

run "rejects_diagnostic_setting_without_destination" {
  command = plan

  variables {
    diagnostic_settings = {
      nowhere = {}
    }
  }

  expect_failures = [var.diagnostic_settings]
}

run "rejects_resource_group_id" {
  command = plan

  variables {
    resource_group_name = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
  }

  expect_failures = [var.resource_group_name]
}
