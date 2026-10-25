# =============================================================================
# AZURE MONITOR METRIC ALERT (Microsoft.Insights/metricAlerts)
# =============================================================================
# Criteria are always sent as `MultipleResourceMultipleMetricCriteria`. It is
# the only criteria type that carries dynamic thresholds and multi-resource
# scopes, it accepts a single-resource scope as well, and it is what the azurerm
# provider sends once a target resource type is set — so one discriminator
# serves every input, and a rule adopted from azurerm keeps the one it has.
#
# A criterion's `name` is its map key and is visible in ARM. A rule adopted from
# azurerm carries that provider's `Metric1`, `Metric2`, ... names; keep them as
# keys, or the next write renames the criteria.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # The input stays a plain resource group name (AVM's shape); the subscription
  # comes from the configured provider, so an aliased or multi-subscription
  # caller still lands in the right place.
  resource_group_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}/resourceGroups/${var.resource_group_name}"

  static_criteria = [
    for name, criterion in var.criteria : {
      criterionType        = "StaticThresholdCriterion"
      name                 = name
      metricNamespace      = criterion.metric_namespace
      metricName           = criterion.metric_name
      timeAggregation      = criterion.aggregation
      operator             = criterion.operator
      threshold            = criterion.threshold
      skipMetricValidation = criterion.skip_metric_validation
      dimensions = [
        for dimension in criterion.dimensions : {
          name     = dimension.name
          operator = dimension.operator
          values   = dimension.values
        }
      ]
    }
  ]

  dynamic_criteria = [
    for name, criterion in var.dynamic_criteria : {
      criterionType    = "DynamicThresholdCriterion"
      name             = name
      metricNamespace  = criterion.metric_namespace
      metricName       = criterion.metric_name
      timeAggregation  = criterion.aggregation
      operator         = criterion.operator
      alertSensitivity = criterion.alert_sensitivity
      failingPeriods = {
        numberOfEvaluationPeriods = criterion.failing_periods.number_of_evaluation_periods
        minFailingPeriodsToAlert  = criterion.failing_periods.min_failing_periods_to_alert
      }
      ignoreDataBefore     = criterion.ignore_data_before
      skipMetricValidation = criterion.skip_metric_validation
      dimensions = [
        for dimension in criterion.dimensions : {
          name     = dimension.name
          operator = dimension.operator
          values   = dimension.values
        }
      ]
    }
  ]
}

resource "azapi_resource" "this" {
  location  = var.location
  name      = var.name
  parent_id = local.resource_group_resource_id
  type      = "Microsoft.Insights/metricAlerts@2026-01-01"
  body = {
    properties = {
      actions = [
        for action_group in values(var.action_groups) : {
          actionGroupId     = action_group.action_group_id
          webHookProperties = action_group.webhook_properties
        }
      ]
      autoMitigate = var.auto_mitigate
      criteria = {
        "odata.type" = "Microsoft.Azure.Monitor.MultipleResourceMultipleMetricCriteria"
        allOf        = concat(local.static_criteria, local.dynamic_criteria)
      }
      description          = var.description
      enabled              = var.enabled
      evaluationFrequency  = var.evaluation_frequency
      scopes               = var.scopes
      severity             = var.severity
      targetResourceRegion = var.target_resource_region
      targetResourceType   = var.target_resource_type
      windowSize           = var.window_size
    }
  }
  # ARM stores an unsent `targetResourceRegion` as "" rather than null, so a null
  # left in the body would diff against it on every plan. Omitting nulls keeps the
  # unset optionals (`description`, `ignoreDataBefore`, the target pair) off the
  # wire instead.
  ignore_null_property = true
  tags                 = var.tags
}
