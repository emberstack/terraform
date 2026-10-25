# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "Name of the metric alert rule."
  nullable    = false

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "resource_group_name" {
  type        = string
  description = "Name of the existing resource group to create the alert rule in. Resolved against the provider's subscription."
  nullable    = false
}

variable "scopes" {
  type        = list(string)
  description = <<-EOT
    Resource IDs the alert evaluates. A single resource is the common case. A subscription,
    a resource group, or more than one resource also needs `target_resource_type` and
    `target_resource_region` — ARM rejects the rule without them.
  EOT
  nullable    = false

  validation {
    condition     = length(var.scopes) > 0
    error_message = "scopes must contain at least one resource ID."
  }

  validation {
    condition     = alltrue([for scope in var.scopes : startswith(scope, "/subscriptions/")])
    error_message = "Each scopes entry must be an ARM resource ID starting with /subscriptions/."
  }

  validation {
    condition = (
      (length(var.scopes) == 1 && length(split("/", trim(var.scopes[0], "/"))) > 4)
      || (var.target_resource_type != null && var.target_resource_region != null)
    )
    error_message = "A subscription or resource group scope, or more than one scope, needs both target_resource_type and target_resource_region."
  }
}

# -----------------------------------------------------------------------------
# Optional
# -----------------------------------------------------------------------------

variable "location" {
  type        = string
  default     = "global"
  description = "Location of the alert rule resource. Metric alerts are global resources; leave the default unless a regional rule is required."
  nullable    = false
}

variable "description" {
  type        = string
  default     = null
  description = "Description of the alert rule."
}

variable "enabled" {
  type        = bool
  default     = true
  description = "Whether the alert rule is evaluated."
  nullable    = false
}

variable "severity" {
  type        = number
  default     = 3
  description = "Alert severity, from 0 (critical) to 4 (verbose)."
  nullable    = false

  validation {
    condition     = contains([0, 1, 2, 3, 4], var.severity)
    error_message = "severity must be an integer from 0 to 4."
  }
}

variable "evaluation_frequency" {
  type        = string
  default     = "PT5M"
  description = "How often the rule is evaluated, as an ISO 8601 duration (e.g. `PT1M`, `PT5M`, `PT15M`, `PT1H`)."
  nullable    = false

  validation {
    condition     = can(regex("^P(\\d+D)?(T(\\d+H)?(\\d+M)?)?$", var.evaluation_frequency)) && !contains(["P", "PT"], var.evaluation_frequency)
    error_message = "evaluation_frequency must be an ISO 8601 duration such as PT5M or PT1H."
  }
}

variable "window_size" {
  type        = string
  default     = "PT5M"
  description = "Period the criteria aggregate over, as an ISO 8601 duration (e.g. `PT5M`, `PT1H`, `P1D`). Must be at least `evaluation_frequency`."
  nullable    = false

  validation {
    condition     = can(regex("^P(\\d+D)?(T(\\d+H)?(\\d+M)?)?$", var.window_size)) && !contains(["P", "PT"], var.window_size)
    error_message = "window_size must be an ISO 8601 duration such as PT15M or P1D."
  }
}

variable "auto_mitigate" {
  type        = bool
  default     = true
  description = "Whether a fired alert resolves itself once the criteria stop being met."
  nullable    = false
}

variable "target_resource_type" {
  type        = string
  default     = null
  description = "Resource type of the monitored resources (e.g. `Microsoft.Insights/components`). Required for a subscription or resource group scope, or more than one scope."
}

variable "target_resource_region" {
  type        = string
  default     = null
  description = "Region of the monitored resources. Required for a subscription or resource group scope, or more than one scope."
}

variable "criteria" {
  type = map(object({
    metric_namespace       = string
    metric_name            = string
    aggregation            = string
    operator               = string
    threshold              = number
    skip_metric_validation = optional(bool, false)
    dimensions = optional(list(object({
      name     = string
      operator = string
      values   = list(string)
    })), [])
  }))
  default     = {}
  description = <<-EOT
    Static-threshold criteria, keyed by criterion name. The key is sent as the criterion's
    `name` and is visible in ARM; keep it stable when adopting an existing rule (the azurerm
    provider named criteria `Metric1`, `Metric2`, ...).

    - `aggregation` - `Average`, `Count`, `Maximum`, `Minimum` or `Total`.
    - `operator` - `Equals`, `GreaterThan`, `GreaterThanOrEqual`, `LessThan` or `LessThanOrEqual`.
    - `skip_metric_validation` - create the rule on a custom metric that is not emitted yet.
    - `dimensions` - filters, each with `operator` `Include` or `Exclude`.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for c in values(var.criteria) : contains(["Average", "Count", "Maximum", "Minimum", "Total"], c.aggregation)])
    error_message = "Each criteria aggregation must be one of Average, Count, Maximum, Minimum, Total."
  }

  validation {
    condition     = alltrue([for c in values(var.criteria) : contains(["Equals", "GreaterThan", "GreaterThanOrEqual", "LessThan", "LessThanOrEqual"], c.operator)])
    error_message = "Each criteria operator must be one of Equals, GreaterThan, GreaterThanOrEqual, LessThan, LessThanOrEqual."
  }

  validation {
    condition     = alltrue([for c in values(var.criteria) : alltrue([for d in c.dimensions : contains(["Include", "Exclude"], d.operator)])])
    error_message = "Each dimension operator must be Include or Exclude."
  }
}

variable "dynamic_criteria" {
  type = map(object({
    metric_namespace  = string
    metric_name       = string
    aggregation       = string
    operator          = string
    alert_sensitivity = string
    failing_periods = optional(object({
      number_of_evaluation_periods = number
      min_failing_periods_to_alert = number
      }), {
      number_of_evaluation_periods = 4
      min_failing_periods_to_alert = 4
    })
    ignore_data_before     = optional(string, null)
    skip_metric_validation = optional(bool, false)
    dimensions = optional(list(object({
      name     = string
      operator = string
      values   = list(string)
    })), [])
  }))
  default     = {}
  description = <<-EOT
    Dynamic-threshold criteria, keyed by criterion name. Names share one namespace with
    `criteria` — a key may not appear in both.

    - `aggregation` - `Average`, `Count`, `Maximum`, `Minimum` or `Total`.
    - `operator` - `GreaterOrLessThan`, `GreaterThan` or `LessThan`.
    - `alert_sensitivity` - `High`, `Medium` or `Low`.
    - `failing_periods` - violations (`min_failing_periods_to_alert`) out of lookback points
      (`number_of_evaluation_periods`) needed to fire. Defaults to 4 of 4.
    - `ignore_data_before` - ISO 8601 date the learning history starts from.
    - `dimensions` - filters, each with `operator` `Include` or `Exclude`.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for c in values(var.dynamic_criteria) : contains(["Average", "Count", "Maximum", "Minimum", "Total"], c.aggregation)])
    error_message = "Each dynamic_criteria aggregation must be one of Average, Count, Maximum, Minimum, Total."
  }

  validation {
    condition     = alltrue([for c in values(var.dynamic_criteria) : contains(["GreaterOrLessThan", "GreaterThan", "LessThan"], c.operator)])
    error_message = "Each dynamic_criteria operator must be one of GreaterOrLessThan, GreaterThan, LessThan."
  }

  validation {
    condition     = alltrue([for c in values(var.dynamic_criteria) : contains(["High", "Medium", "Low"], c.alert_sensitivity)])
    error_message = "Each dynamic_criteria alert_sensitivity must be one of High, Medium, Low."
  }

  validation {
    condition = alltrue([
      for c in values(var.dynamic_criteria) :
      c.failing_periods.min_failing_periods_to_alert >= 1
      && c.failing_periods.min_failing_periods_to_alert <= c.failing_periods.number_of_evaluation_periods
    ])
    error_message = "Each dynamic_criteria failing_periods.min_failing_periods_to_alert must be between 1 and number_of_evaluation_periods."
  }

  validation {
    condition     = alltrue([for c in values(var.dynamic_criteria) : alltrue([for d in c.dimensions : contains(["Include", "Exclude"], d.operator)])])
    error_message = "Each dimension operator must be Include or Exclude."
  }

  # The two cross-map checks live here only: a validation on `criteria` naming
  # this variable as well would make the pair a dependency cycle.
  validation {
    condition     = length(var.criteria) + length(var.dynamic_criteria) > 0
    error_message = "At least one entry in criteria or dynamic_criteria is required."
  }

  validation {
    condition     = length(setintersection(keys(var.criteria), keys(var.dynamic_criteria))) == 0
    error_message = "A criterion name may appear in criteria or dynamic_criteria, not both — ARM requires unique names across the rule."
  }
}

variable "action_groups" {
  type = map(object({
    action_group_id    = string
    webhook_properties = optional(map(string), {})
  }))
  default     = {}
  description = <<-EOT
    Action groups notified when the alert fires, keyed by a stable identifier. The key is
    Terraform identity only and is never sent to Azure. `webhook_properties` are appended to
    the payload a webhook receiver gets.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for a in values(var.action_groups) : can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Insights/actionGroups/[^/]+$", a.action_group_id))])
    error_message = "Each action_groups action_group_id must be the resource ID of a Microsoft.Insights/actionGroups resource."
  }
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Tags applied to the alert rule."
}
