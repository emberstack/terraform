# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "log_analytics_workspace_resource_id" {
  type        = string
  description = "ARM resource ID of the existing Log Analytics workspace that has Microsoft Sentinel enabled. Used directly as each rule's `parent_id`."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourcegroups/[^/]+/providers/microsoft\\.operationalinsights/workspaces/[^/]+$", var.log_analytics_workspace_resource_id))
    error_message = "log_analytics_workspace_resource_id must be an ARM resource ID of a Log Analytics workspace, e.g. /subscriptions/<sub>/resourceGroups/<rg>/providers/Microsoft.OperationalInsights/workspaces/<workspace>."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "alert_rules" {
  type = map(object({
    name                 = optional(string)
    display_name         = string
    description          = optional(string)
    enabled              = optional(bool, true)
    severity             = string
    query                = string
    query_frequency      = string
    query_period         = string
    trigger_operator     = optional(string, "GreaterThan")
    trigger_threshold    = optional(number, 0)
    suppression_duration = optional(string)
    tactics              = optional(list(string), [])
    techniques           = optional(list(string), [])
    event_grouping       = optional(string, "SingleAlert")
    custom_details       = optional(map(string), {})
    entity_mappings = optional(list(object({
      entity_type = string
      field_mappings = list(object({
        identifier  = string
        column_name = string
      }))
    })), [])
    alert_details_override = optional(object({
      display_name_format  = optional(string)
      description_format   = optional(string)
      severity_column_name = optional(string)
      tactics_column_name  = optional(string)
    }))
    incident = optional(object({
      create = optional(bool, true)
      grouping = optional(object({
        enabled                 = optional(bool, false)
        lookback_duration       = optional(string, "PT5H")
        matching_method         = optional(string, "AllEntities")
        reopen_closed_incident  = optional(bool, false)
        group_by_entities       = optional(list(string), [])
        group_by_alert_details  = optional(list(string), [])
        group_by_custom_details = optional(list(string), [])
      }), {})
    }), {})
  }))
  default     = {}
  nullable    = false
  description = <<-EOT
    Map of scheduled analytics rules, keyed by a stable identifier. The map key is the `for_each`
    address and the output key, and the rule's ARM name when `name` is unset.

    Fields:
    - `name` (optional) — ARM rule name; defaults to the map key.
    - `display_name` (required) — rule name shown in the portal and on its alerts.
    - `description` (optional) — omitted from the request when unset.
    - `enabled` (optional) — defaults to true.
    - `severity` (required) — `High`, `Medium`, `Low` or `Informational`.
    - `query` (required) — the KQL the rule runs. May read other workspaces through `workspace()`.
    - `query_frequency` / `query_period` (required) — how often the query runs and how far back it
      looks, as `PT<n>M`, `PT<n>H` or `P<n>D`. Both must be 5 minutes to 14 days, and the period
      at least as long as the frequency.
    - `trigger_operator` / `trigger_threshold` (optional) — alert when the result count compares
      this way to the threshold. Defaults to `GreaterThan` 0, i.e. any result.
    - `suppression_duration` (optional) — stop running the query for this long after it alerts,
      as an ISO 8601 duration. Unset disables suppression.
    - `tactics` / `techniques` (optional) — MITRE ATT&CK tactics, and technique IDs such as `T1071`.
    - `event_grouping` (optional) — `SingleAlert` (one alert per run, the default) or
      `AlertPerResult` (one alert per result row, at most 150 per run).
    - `custom_details` (optional) — alert custom detail name to result column, at most 20.
    - `entity_mappings` (optional) — at most 10 entities, each an `entity_type` plus a list of
      `identifier` / `column_name` pairs.
    - `alert_details_override` (optional) — `{{column}}` formats for the alert name and
      description, and columns to take severity and tactics from.
    - `incident` (optional) — `create` (default true) and `grouping` of this rule's alerts into
      incidents: `enabled` (default false), `lookback_duration` (default `PT5H`),
      `matching_method` (`AllEntities`, `AnyAlert` or `Selected`; `Selected` needs at least one
      `group_by_*` list), `reopen_closed_incident` and the `group_by_*` lists.
  EOT

  validation {
    condition     = alltrue([for k, v in var.alert_rules : length(trimspace(coalesce(v.name, k))) > 0 && !strcontains(coalesce(v.name, k), "/")])
    error_message = "Each rule name (its `name`, or the map key when unset) must be non-empty and must not contain `/`."
  }

  # ARM names are case-insensitive, so two entries differing only in case would
  # address the same rule and overwrite each other on every apply.
  validation {
    condition     = length(distinct([for k, v in var.alert_rules : lower(coalesce(v.name, k))])) == length(var.alert_rules)
    error_message = "Rule names must be unique within the workspace, compared case-insensitively."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : length(trimspace(v.display_name)) > 0 && length(trimspace(v.query)) > 0])
    error_message = "Each rule needs a non-empty `display_name` and `query`."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : contains(["High", "Medium", "Low", "Informational"], v.severity)])
    error_message = "Each rule's `severity` must be one of High, Medium, Low or Informational."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.alert_rules : [
        for d in compact([v.query_frequency, v.query_period]) : can(regex("^(PT[0-9]+[MH]|P[0-9]+D)$", d))
      ]
    ]))
    error_message = "Each rule's `query_frequency` and `query_period` must be written PT<n>M, PT<n>H or P<n>D."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : contains(["Equal", "GreaterThan", "LessThan", "NotEqual"], v.trigger_operator)])
    error_message = "Each rule's `trigger_operator` must be one of Equal, GreaterThan, LessThan or NotEqual."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : v.trigger_threshold >= 0 && floor(v.trigger_threshold) == v.trigger_threshold])
    error_message = "Each rule's `trigger_threshold` must be a whole number, zero or more."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : v.suppression_duration == null || can(regex("^P(?:[0-9]+D)?(?:T(?:[0-9]+H)?(?:[0-9]+M)?)?$", coalesce(v.suppression_duration, "x"))) && v.suppression_duration != "P" && v.suppression_duration != "PT"])
    error_message = "Each rule's `suppression_duration`, when set, must be an ISO 8601 duration such as PT5H, PT30M or P1D."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.alert_rules : [
        for t in v.tactics : contains([
          "Collection", "CommandAndControl", "CredentialAccess", "DefenseEvasion", "Discovery", "Execution",
          "Exfiltration", "Impact", "ImpairProcessControl", "InhibitResponseFunction", "InitialAccess",
          "LateralMovement", "Persistence", "PreAttack", "PrivilegeEscalation", "Reconnaissance", "ResourceDevelopment",
        ], t)
      ]
    ]))
    error_message = "Each rule's `tactics` entries must be Sentinel tactic names, e.g. CommandAndControl, InitialAccess, Impact."
  }

  validation {
    condition     = alltrue(flatten([for k, v in var.alert_rules : [for t in v.techniques : can(regex("^T[0-9]{4}$", t))]]))
    error_message = "Each rule's `techniques` entries must be MITRE ATT&CK technique IDs such as T1071, without a sub-technique suffix."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : contains(["SingleAlert", "AlertPerResult"], v.event_grouping)])
    error_message = "Each rule's `event_grouping` must be SingleAlert or AlertPerResult."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : length(v.custom_details) <= 20])
    error_message = "Each rule may have at most 20 `custom_details`."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : length(v.entity_mappings) <= 10])
    error_message = "Each rule may have at most 10 `entity_mappings`."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.alert_rules : [
        for e in v.entity_mappings : contains([
          "Account", "AzureResource", "CloudApplication", "DNS", "File", "FileHash", "Host", "IP", "Mailbox",
          "MailCluster", "MailMessage", "Malware", "Process", "RegistryKey", "RegistryValue", "SecurityGroup",
          "SubmissionMail", "URL",
        ], e.entity_type) && length(e.field_mappings) > 0
      ]
    ]))
    error_message = "Each entity mapping needs a Sentinel entity type (e.g. IP, Account, Host, URL) and at least one field mapping."
  }

  validation {
    condition = alltrue([
      for k, v in var.alert_rules : v.alert_details_override == null ? true : anytrue([
        for x in values(v.alert_details_override) : x != null
      ])
    ])
    error_message = "An `alert_details_override` must set at least one of its fields; leave it unset otherwise."
  }

  validation {
    condition = alltrue([
      for k, v in var.alert_rules : contains(["AllEntities", "AnyAlert", "Selected"], v.incident.grouping.matching_method) && (
        v.incident.grouping.matching_method != "Selected" || length(concat(
          v.incident.grouping.group_by_entities, v.incident.grouping.group_by_alert_details, v.incident.grouping.group_by_custom_details
        )) > 0
      )
    ])
    error_message = "Incident grouping `matching_method` must be AllEntities, AnyAlert or Selected, and Selected needs at least one `group_by_*` entry."
  }

  validation {
    condition = alltrue(flatten([
      for k, v in var.alert_rules : [for d in v.incident.grouping.group_by_alert_details : contains(["DisplayName", "Severity"], d)]
    ]))
    error_message = "Incident grouping `group_by_alert_details` entries must be DisplayName or Severity."
  }

  validation {
    condition     = alltrue([for k, v in var.alert_rules : can(regex("^P(?:[0-9]+D)?(?:T(?:[0-9]+H)?(?:[0-9]+M)?)?$", v.incident.grouping.lookback_duration)) && !contains(["P", "PT"], v.incident.grouping.lookback_duration)])
    error_message = "Incident grouping `lookback_duration` must be an ISO 8601 duration such as PT5H or P1D."
  }
}
