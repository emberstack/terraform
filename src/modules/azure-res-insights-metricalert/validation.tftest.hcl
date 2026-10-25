# =============================================================================
# azure-res-insights-metricalert tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# The positive runs are the ones that construct the request body — an
# `expect_failures`-only suite never does, so a bad attribute reference would
# pass it green.
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
}

variables {
  name                = "alert-example"
  resource_group_name = "rg-example"
  scopes              = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Insights/components/appi-example"]

  criteria = {
    Metric1 = {
      metric_namespace = "Azure.ApplicationInsights"
      metric_name      = "example_metric"
      aggregation      = "Average"
      operator         = "LessThan"
      threshold        = -100
    }
  }

  action_groups = {
    primary = {
      action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Insights/actionGroups/ag-example"
    }
  }
}

# =============================================================================
# POSITIVE — resource graph and request body must actually evaluate
# =============================================================================

run "plans_single_resource_static_alert" {
  command = plan

  assert {
    condition     = azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"
    error_message = "the alert must be parented on the resource group in the provider's subscription"
  }
  assert {
    condition     = azapi_resource.this.location == "global"
    error_message = "location must default to global"
  }
  assert {
    condition     = azapi_resource.this.body.properties.criteria["odata.type"] == "Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria"
    error_message = "criteria must always use the multiple-resource discriminator"
  }
  assert {
    condition     = length(azapi_resource.this.body.properties.criteria.allOf) == 1 && azapi_resource.this.body.properties.criteria.allOf[0].criterionType == "StaticThresholdCriterion" && azapi_resource.this.body.properties.criteria.allOf[0].name == "Metric1"
    error_message = "a static criterion must be sent as StaticThresholdCriterion, named by its map key"
  }
  assert {
    condition     = azapi_resource.this.body.properties.criteria.allOf[0].timeAggregation == "Average" && azapi_resource.this.body.properties.criteria.allOf[0].threshold == -100
    error_message = "aggregation and threshold must map to timeAggregation and threshold"
  }
  assert {
    condition     = azapi_resource.this.body.properties.actions[0].actionGroupId == var.action_groups.primary.action_group_id && length(azapi_resource.this.body.properties.actions[0].webHookProperties) == 0
    error_message = "each action group must be sent with its ID and empty webhook properties by default"
  }
  assert {
    condition     = azapi_resource.this.body.properties.severity == 3 && azapi_resource.this.body.properties.evaluationFrequency == "PT5M" && azapi_resource.this.body.properties.windowSize == "PT5M" && azapi_resource.this.body.properties.autoMitigate == true
    error_message = "severity, frequency, window and auto-mitigation must take their defaults"
  }
  assert {
    condition     = azapi_resource.this.ignore_null_property == true
    error_message = "unset optionals must be kept off the wire"
  }
}

run "plans_multi_resource_dynamic_alert" {
  command = plan

  variables {
    scopes = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Compute/virtualMachines/vm-01",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Compute/virtualMachines/vm-02",
    ]
    target_resource_type   = "Microsoft.Compute/virtualMachines"
    target_resource_region = "westeurope"
    criteria               = {}
    dynamic_criteria = {
      cpu = {
        metric_namespace  = "Microsoft.Compute/virtualMachines"
        metric_name       = "Percentage CPU"
        aggregation       = "Average"
        operator          = "GreaterThan"
        alert_sensitivity = "Medium"
      }
    }
  }

  assert {
    condition     = azapi_resource.this.body.properties.criteria.allOf[0].criterionType == "DynamicThresholdCriterion" && azapi_resource.this.body.properties.criteria.allOf[0].alertSensitivity == "Medium"
    error_message = "a dynamic criterion must be sent as DynamicThresholdCriterion with its sensitivity"
  }
  assert {
    condition     = azapi_resource.this.body.properties.criteria.allOf[0].failingPeriods.numberOfEvaluationPeriods == 4 && azapi_resource.this.body.properties.criteria.allOf[0].failingPeriods.minFailingPeriodsToAlert == 4
    error_message = "failing periods must default to 4 of 4"
  }
  assert {
    condition     = azapi_resource.this.body.properties.targetResourceType == "Microsoft.Compute/virtualMachines" && azapi_resource.this.body.properties.targetResourceRegion == "westeurope"
    error_message = "a multi-resource rule must carry its target type and region"
  }
}

run "orders_static_criteria_before_dynamic" {
  command = plan

  variables {
    dynamic_criteria = {
      Metric2 = {
        metric_namespace  = "Azure.ApplicationInsights"
        metric_name       = "example_metric"
        aggregation       = "Average"
        operator          = "LessThan"
        alert_sensitivity = "Low"
      }
    }
  }

  assert {
    condition     = [for c in azapi_resource.this.body.properties.criteria.allOf : c.name] == ["Metric1", "Metric2"]
    error_message = "static criteria must precede dynamic criteria in allOf"
  }
}

# =============================================================================
# NEGATIVE — each validation must fire
# =============================================================================

run "rejects_severity_out_of_range" {
  command = plan
  variables {
    severity = 5
  }
  expect_failures = [var.severity]
}

run "rejects_rule_without_criteria" {
  command = plan
  variables {
    criteria = {}
  }
  expect_failures = [var.dynamic_criteria]
}

run "rejects_name_in_both_criteria_maps" {
  command = plan
  variables {
    dynamic_criteria = {
      Metric1 = {
        metric_namespace  = "Azure.ApplicationInsights"
        metric_name       = "example_metric"
        aggregation       = "Average"
        operator          = "LessThan"
        alert_sensitivity = "Low"
      }
    }
  }
  expect_failures = [var.dynamic_criteria]
}

run "rejects_resource_group_scope_without_targets" {
  command = plan
  variables {
    scopes = ["/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example"]
  }
  expect_failures = [var.scopes]
}

run "rejects_unknown_static_operator" {
  command = plan
  variables {
    criteria = {
      Metric1 = {
        metric_namespace = "Azure.ApplicationInsights"
        metric_name      = "example_metric"
        aggregation      = "Average"
        operator         = "NotEquals"
        threshold        = 1
      }
    }
  }
  expect_failures = [var.criteria]
}

run "rejects_unsupported_dimension_operator" {
  command = plan
  variables {
    criteria = {
      Metric1 = {
        metric_namespace = "Azure.ApplicationInsights"
        metric_name      = "example_metric"
        aggregation      = "Average"
        operator         = "LessThan"
        threshold        = 1
        dimensions = [
          { name = "cloud/roleName", operator = "StartsWith", values = ["api"] },
        ]
      }
    }
  }
  expect_failures = [var.criteria]
}

run "rejects_more_failing_periods_than_lookback" {
  command = plan
  variables {
    criteria = {}
    dynamic_criteria = {
      cpu = {
        metric_namespace  = "Microsoft.Compute/virtualMachines"
        metric_name       = "Percentage CPU"
        aggregation       = "Average"
        operator          = "GreaterThan"
        alert_sensitivity = "High"
        failing_periods = {
          number_of_evaluation_periods = 2
          min_failing_periods_to_alert = 3
        }
      }
    }
  }
  expect_failures = [var.dynamic_criteria]
}

run "rejects_non_action_group_id" {
  command = plan
  variables {
    action_groups = {
      primary = {
        action_group_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Web/sites/app-example"
      }
    }
  }
  expect_failures = [var.action_groups]
}

run "rejects_non_iso8601_frequency" {
  command = plan
  variables {
    evaluation_frequency = "5m"
  }
  expect_failures = [var.evaluation_frequency]
}
