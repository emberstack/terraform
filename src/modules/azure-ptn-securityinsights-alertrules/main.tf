# =============================================================================
# MICROSOFT SENTINEL SCHEDULED ANALYTICS RULES
# =============================================================================
# Scheduled analytics rules on a Sentinel-enabled Log Analytics workspace owned
# elsewhere. Rules are extension resources of the workspace, so several
# configurations can each contribute their own rules without redeclaring it.
#
# Only keys the caller set are sent: an unset description, empty tactics, entity
# mappings or custom details, and an unset alert-details override are omitted
# from the body rather than sent as null or [], so ARM's own defaults are never
# overwritten and never diffed.
#
# A rule whose query reads another subscription's workspace through workspace()
# runs with the credentials of the identity that created it, not an independent
# token — it is auto-disabled if that identity later loses read access there.
# =============================================================================

locals {
  # Minutes for the ISO 8601 subset the inputs accept: PT<n>M, PT<n>H or P<n>D.
  # Anything else maps to -1, which the preconditions reject.
  duration_minutes = {
    for k, v in var.alert_rules : k => {
      for field, value in { frequency = v.query_frequency, period = v.query_period } : field => (
        can(regex("^PT([0-9]+)M$", value)) ? tonumber(regex("^PT([0-9]+)M$", value)[0]) :
        can(regex("^PT([0-9]+)H$", value)) ? tonumber(regex("^PT([0-9]+)H$", value)[0]) * 60 :
        can(regex("^P([0-9]+)D$", value)) ? tonumber(regex("^P([0-9]+)D$", value)[0]) * 1440 :
        -1
      )
    }
  }
}

resource "azapi_resource" "this" {
  for_each = var.alert_rules

  name      = coalesce(each.value.name, each.key)
  parent_id = var.log_analytics_workspace_resource_id
  type      = "Microsoft.SecurityInsights/alertRules@2025-09-01"
  body = {
    kind = "Scheduled"
    properties = merge(concat(
      [{
        displayName         = each.value.display_name
        enabled             = each.value.enabled
        severity            = each.value.severity
        query               = each.value.query
        queryFrequency      = each.value.query_frequency
        queryPeriod         = each.value.query_period
        triggerOperator     = each.value.trigger_operator
        triggerThreshold    = each.value.trigger_threshold
        suppressionEnabled  = each.value.suppression_duration != null
        suppressionDuration = coalesce(each.value.suppression_duration, "PT5H")
        eventGroupingSettings = {
          aggregationKind = each.value.event_grouping
        }
        incidentConfiguration = {
          createIncident = each.value.incident.create
          groupingConfiguration = {
            enabled              = each.value.incident.grouping.enabled
            lookbackDuration     = each.value.incident.grouping.lookback_duration
            matchingMethod       = each.value.incident.grouping.matching_method
            reopenClosedIncident = each.value.incident.grouping.reopen_closed_incident
            groupByEntities      = each.value.incident.grouping.group_by_entities
            groupByAlertDetails  = each.value.incident.grouping.group_by_alert_details
            groupByCustomDetails = each.value.incident.grouping.group_by_custom_details
          }
        }
      }],
      [for d in(each.value.description == null ? [] : [each.value.description]) : { description = d }],
      [for t in(length(each.value.tactics) == 0 ? [] : [each.value.tactics]) : { tactics = t }],
      [for t in(length(each.value.techniques) == 0 ? [] : [each.value.techniques]) : { techniques = t }],
      [for c in(length(each.value.custom_details) == 0 ? [] : [each.value.custom_details]) : { customDetails = c }],
      [for m in(length(each.value.entity_mappings) == 0 ? [] : [each.value.entity_mappings]) : {
        entityMappings = [
          for e in m : {
            entityType = e.entity_type
            fieldMappings = [
              for f in e.field_mappings : {
                identifier = f.identifier
                columnName = f.column_name
              }
            ]
          }
        ]
      }],
      [for o in(each.value.alert_details_override == null ? [] : [each.value.alert_details_override]) : {
        alertDetailsOverride = merge(concat(
          [for x in(o.display_name_format == null ? [] : [o.display_name_format]) : { alertDisplayNameFormat = x }],
          [for x in(o.description_format == null ? [] : [o.description_format]) : { alertDescriptionFormat = x }],
          [for x in(o.severity_column_name == null ? [] : [o.severity_column_name]) : { alertSeverityColumnName = x }],
          [for x in(o.tactics_column_name == null ? [] : [o.tactics_column_name]) : { alertTacticsColumnName = x }],
        )...)
      }],
    )...)
  }

  lifecycle {
    precondition {
      condition     = local.duration_minutes[each.key].frequency >= 5 && local.duration_minutes[each.key].frequency <= 20160
      error_message = "alert_rules[\"${each.key}\"].query_frequency must be from 5 minutes to 14 days, written PT<n>M, PT<n>H or P<n>D."
    }
    precondition {
      condition     = local.duration_minutes[each.key].period >= 5 && local.duration_minutes[each.key].period <= 20160
      error_message = "alert_rules[\"${each.key}\"].query_period must be from 5 minutes to 14 days, written PT<n>M, PT<n>H or P<n>D."
    }
    precondition {
      condition     = local.duration_minutes[each.key].period >= local.duration_minutes[each.key].frequency
      error_message = "alert_rules[\"${each.key}\"].query_period must be at least as long as query_frequency."
    }
  }
}
