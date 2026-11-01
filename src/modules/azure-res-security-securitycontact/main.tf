# =============================================================================
# DEFENDER FOR CLOUD SECURITY CONTACT (Microsoft.Security/securityContacts)
# =============================================================================
# Who Defender for Cloud emails about alerts and attack paths in one
# subscription — the provider's. ARM accepts exactly one contact per
# subscription, named `default`.
#
# Only preview API versions have shipped since 2020; 2023-12-01-preview is the
# first with per-source thresholds (`notificationsSources`) and the newest.
#
# Nothing here sets `response_export_values` or `ignore_null_property`: a change
# to either alone is a PUT, so adopting the existing contact by `terraform
# import` would cost a write. Unset optional fields are left out of the body.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  # Attack paths first, then alerts: the order ARM returns them in. azapi
  # compares lists by position, so the other order would diff on every plan.
  notification_sources = concat(
    [for risk in(var.attack_path_minimal_risk == null ? [] : [var.attack_path_minimal_risk]) : {
      minimalRiskLevel = risk
      sourceType       = "AttackPath"
    }],
    [for severity in(var.alert_minimal_severity == null ? [] : [var.alert_minimal_severity]) : {
      minimalSeverity = severity
      sourceType      = "Alert"
    }],
  )
}

resource "azapi_resource" "this" {
  name      = "default"
  parent_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"
  type      = "Microsoft.Security/securityContacts@2023-12-01-preview"
  body = {
    properties = merge(
      {
        emails    = join(";", var.emails)
        isEnabled = var.enabled
        notificationsByRole = {
          roles = var.notify_roles
          state = length(var.notify_roles) > 0 ? "On" : "Off"
        }
        notificationsSources = local.notification_sources
      },
      [for phone in(var.phone == null ? [] : [var.phone]) : { phone = phone }]...
    )
  }
}
