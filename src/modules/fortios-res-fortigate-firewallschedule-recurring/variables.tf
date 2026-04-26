# =============================================================================
# firewall.schedule/recurring — a daily-pattern time window.
# =============================================================================
# Used wherever FortiOS accepts a `schedule` reference: VAP `schedule`, ARRP
# `darrp_optimize_schedules`, firewall policies, etc.
# =============================================================================

variable "name" {
  description = "Schedule mkey. Referenced by name from VAPs / policies / ARRP profiles."
  type        = string
}

variable "start" {
  description = "Window start as 'HH:MM' (24h)."
  type        = string
}

variable "end" {
  description = "Window end as 'HH:MM' (24h)."
  type        = string
}

variable "day" {
  description = "Space-separated days the schedule is active. Use 'sunday monday tuesday wednesday thursday friday saturday' for daily."
  type        = string
  default     = "sunday monday tuesday wednesday thursday friday saturday"
}

variable "color" {
  description = "GUI colour index for the schedule icon. `0` uses the FortiOS default colour."
  type        = number
  default     = 0
}

variable "fabric_object" {
  description = "Set 'enable' to publish this schedule object to Security Fabric peers."
  type        = string
  default     = "disable"
}
