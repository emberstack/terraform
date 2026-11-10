# =============================================================================
# azure-ptn-securityinsights-alertrules tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation or a resource precondition, and the positive runs need a resource
# graph but not a real subscription.
#
# The positive runs are the ones that construct the resource graph and evaluate
# the outputs — an `expect_failures`-only suite never does, so a bad attribute
# reference would pass it green.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {}

variables {
  log_analytics_workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_minimal_rule_with_defaults_and_omits_unset_keys" {
  command = plan

  variables {
    alert_rules = {
      minimal = {
        display_name    = "Example minimal rule"
        severity        = "Low"
        query           = "Heartbeat | take 1"
        query_frequency = "PT1H"
        query_period    = "PT1H"
      }
    }
  }

  assert {
    condition     = azapi_resource.this["minimal"].name == "minimal" && azapi_resource.this["minimal"].parent_id == var.log_analytics_workspace_resource_id
    error_message = "the ARM name must default to the map key and the rule must be parented on the workspace"
  }
  assert {
    condition     = azapi_resource.this["minimal"].body.kind == "Scheduled"
    error_message = "the rule must be sent as kind Scheduled"
  }
  assert {
    condition = alltrue([
      for key in ["description", "tactics", "techniques", "customDetails", "entityMappings", "alertDetailsOverride"] :
      !contains(keys(azapi_resource.this["minimal"].body.properties), key)
    ])
    error_message = "unset optional keys must be omitted from the body, not sent as null or []"
  }
  assert {
    condition     = azapi_resource.this["minimal"].body.properties.enabled == true && azapi_resource.this["minimal"].body.properties.triggerOperator == "GreaterThan" && azapi_resource.this["minimal"].body.properties.triggerThreshold == 0
    error_message = "enabled must default to true and the trigger to GreaterThan 0"
  }
  assert {
    condition     = azapi_resource.this["minimal"].body.properties.suppressionEnabled == false && azapi_resource.this["minimal"].body.properties.suppressionDuration == "PT5H"
    error_message = "no suppression_duration must send suppression disabled with the PT5H placeholder ARM requires"
  }
  assert {
    condition     = azapi_resource.this["minimal"].body.properties.eventGroupingSettings.aggregationKind == "SingleAlert"
    error_message = "event grouping must default to SingleAlert"
  }
  assert {
    condition = (
      azapi_resource.this["minimal"].body.properties.incidentConfiguration.createIncident == true &&
      azapi_resource.this["minimal"].body.properties.incidentConfiguration.groupingConfiguration.enabled == false &&
      azapi_resource.this["minimal"].body.properties.incidentConfiguration.groupingConfiguration.matchingMethod == "AllEntities" &&
      azapi_resource.this["minimal"].body.properties.incidentConfiguration.groupingConfiguration.lookbackDuration == "PT5H"
    )
    error_message = "incidents must default to created, ungrouped, AllEntities over PT5H"
  }
  assert {
    condition     = output.alert_rules["minimal"].display_name == "Example minimal rule" && output.log_analytics_workspace_resource_id == var.log_analytics_workspace_resource_id
    error_message = "outputs must evaluate"
  }
}

run "plans_full_rule_with_every_optional_field" {
  command = plan

  variables {
    alert_rules = {
      full = {
        name                 = "Example-Full-Rule"
        display_name         = "Example full rule"
        description          = "Fires on anything."
        enabled              = false
        severity             = "High"
        query                = "Heartbeat | project Computer, ComputerIP"
        query_frequency      = "PT10M"
        query_period         = "P14D"
        trigger_operator     = "GreaterThan"
        trigger_threshold    = 3
        suppression_duration = "PT1H"
        tactics              = ["CommandAndControl", "Impact"]
        techniques           = ["T1071"]
        event_grouping       = "AlertPerResult"
        custom_details       = { Host = "Computer" }
        entity_mappings = [
          { entity_type = "IP", field_mappings = [{ identifier = "Address", column_name = "ComputerIP" }] },
        ]
        alert_details_override = {
          display_name_format = "Heartbeat from {{Computer}}"
        }
        incident = {
          grouping = {
            enabled           = true
            matching_method   = "Selected"
            group_by_entities = ["IP"]
          }
        }
      }
    }
  }

  assert {
    condition     = azapi_resource.this["full"].name == "Example-Full-Rule"
    error_message = "an explicit name must be honoured"
  }
  assert {
    condition = (
      azapi_resource.this["full"].body.properties.description == "Fires on anything." &&
      azapi_resource.this["full"].body.properties.enabled == false &&
      azapi_resource.this["full"].body.properties.triggerThreshold == 3 &&
      jsonencode(azapi_resource.this["full"].body.properties.tactics) == jsonencode(["CommandAndControl", "Impact"]) &&
      jsonencode(azapi_resource.this["full"].body.properties.techniques) == jsonencode(["T1071"]) &&
      azapi_resource.this["full"].body.properties.customDetails.Host == "Computer"
    )
    error_message = "set optional fields must pass through"
  }
  assert {
    condition     = azapi_resource.this["full"].body.properties.suppressionEnabled == true && azapi_resource.this["full"].body.properties.suppressionDuration == "PT1H"
    error_message = "a suppression_duration must enable suppression with that duration"
  }
  assert {
    condition     = azapi_resource.this["full"].body.properties.entityMappings[0].entityType == "IP" && azapi_resource.this["full"].body.properties.entityMappings[0].fieldMappings[0].columnName == "ComputerIP"
    error_message = "entity mappings must be translated to entityType / fieldMappings"
  }
  assert {
    condition = (
      azapi_resource.this["full"].body.properties.alertDetailsOverride.alertDisplayNameFormat == "Heartbeat from {{Computer}}" &&
      !contains(keys(azapi_resource.this["full"].body.properties.alertDetailsOverride), "alertDescriptionFormat")
    )
    error_message = "the override must carry only the formats that were set"
  }
  assert {
    condition     = jsonencode(azapi_resource.this["full"].body.properties.incidentConfiguration.groupingConfiguration.groupByEntities) == jsonencode(["IP"]) && azapi_resource.this["full"].body.properties.eventGroupingSettings.aggregationKind == "AlertPerResult"
    error_message = "incident grouping and event grouping must pass through"
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_non_workspace_resource_id" {
  command = plan

  variables {
    log_analytics_workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Storage/storageAccounts/stexample"
  }

  expect_failures = [var.log_analytics_workspace_resource_id]
}

run "rejects_unknown_severity" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Critical", query = "T", query_frequency = "PT1H", query_period = "PT1H" }
    }
  }

  expect_failures = [var.alert_rules]
}

run "rejects_unsupported_duration_format" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT1H30M", query_period = "PT2H" }
    }
  }

  expect_failures = [var.alert_rules]
}

run "rejects_names_differing_only_in_case" {
  command = plan

  variables {
    alert_rules = {
      rule-a = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT1H", query_period = "PT1H" }
      RULE-A = { display_name = "y", severity = "Low", query = "T", query_frequency = "PT1H", query_period = "PT1H" }
    }
  }

  expect_failures = [var.alert_rules]
}

run "rejects_unknown_tactic" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT1H", query_period = "PT1H", tactics = ["CommandControl"] }
    }
  }

  expect_failures = [var.alert_rules]
}

run "rejects_sub_technique_in_techniques" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT1H", query_period = "PT1H", techniques = ["T1071.001"] }
    }
  }

  expect_failures = [var.alert_rules]
}

run "rejects_empty_alert_details_override" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT1H", query_period = "PT1H", alert_details_override = {} }
    }
  }

  expect_failures = [var.alert_rules]
}

run "rejects_selected_grouping_without_group_by" {
  command = plan

  variables {
    alert_rules = {
      bad = {
        display_name = "x", severity = "Low", query = "T", query_frequency = "PT1H", query_period = "PT1H"
        incident     = { grouping = { enabled = true, matching_method = "Selected" } }
      }
    }
  }

  expect_failures = [var.alert_rules]
}

# =============================================================================
# NEGATIVE — resource preconditions
# =============================================================================

run "rejects_frequency_over_fourteen_days" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "P15D", query_period = "P15D" }
    }
  }

  expect_failures = [azapi_resource.this]
}

run "rejects_frequency_under_five_minutes" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT4M", query_period = "PT1H" }
    }
  }

  expect_failures = [azapi_resource.this]
}

run "rejects_period_shorter_than_frequency" {
  command = plan

  variables {
    alert_rules = {
      bad = { display_name = "x", severity = "Low", query = "T", query_frequency = "PT2H", query_period = "PT1H" }
    }
  }

  expect_failures = [azapi_resource.this]
}
