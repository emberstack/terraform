# =============================================================================
# wireless-controller/setting — vdom-global wireless defaults.
# =============================================================================
# Single-instance per VDOM (mkey is the VDOM name). Country code here is the
# default regulatory domain for every wtp-profile that doesn't override
# `ap_country`. Set this once, leave per-profile `ap_country = "--"` to inherit.
# =============================================================================

variable "country" {
  description = "Two-letter country code (e.g. RO, US, DE). Drives radio channel availability and transmit power limits."
  type        = string
  default     = "--"
}

variable "duplicate_ssid" {
  description = "Allow the same SSID on multiple VAPs. Usually 'disable' unless you need band-specific dual-VAP."
  type        = string
  default     = "disable"
}

variable "fapc_compatibility" {
  description = "Legacy FortiAP-Connect compatibility. 'disable' for modern FortiAP fleets."
  type        = string
  default     = "disable"
}

variable "wfa_compatibility" {
  description = "Wi-Fi Alliance test-mode compatibility. 'disable' for production."
  type        = string
  default     = "disable"
}

variable "phishing_ssid_detect" {
  description = "Log/alert when rogue APs broadcast our SSIDs."
  type        = string
  default     = "enable"
}

variable "fake_ssid_action" {
  description = "Action for phishing SSID detections. 'log' | 'suppress' | 'log suppress'."
  type        = string
  default     = "log"
}

variable "device_weight" {
  description = "Weighting factor for device-identification scoring (0-255)."
  type        = number
  default     = 1
}

variable "device_holdoff" {
  description = "Seconds to hold off after a device-identification event before re-evaluating (default 5)."
  type        = number
  default     = 5
}

variable "device_idle" {
  description = "Minutes before a device is considered idle by the device-id table (default 1440 = 24h)."
  type        = number
  default     = 1440
}

# -----------------------------------------------------------------------------
# DARRP — system-level. Per-profile ARRP can override via
# arrp-profile.override_darrp_optimize = enable.
# -----------------------------------------------------------------------------

variable "darrp_optimize" {
  description = "Full DARRP re-optimization interval (seconds). 86400 = daily."
  type        = number
  default     = 86400
}

variable "darrp_optimize_schedules" {
  description = "List of firewall.schedule.recurring names that gate when DARRP optimization may fire. Default factory schedule 'default-darrp-optimize' runs 01:00-01:30 daily."
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Lifecycle / firmware
# -----------------------------------------------------------------------------

variable "firmware_provision_on_authorization" {
  description = "When 'enable', a newly-authorized FortiAP is auto-flashed to the controller's recommended firmware on first join. Safer in residential when you trust your fleet to be on the latest stable."
  type        = string
  default     = "disable"
}

variable "rolling_wtp_upgrade" {
  description = "When 'enable', FortiAP firmware upgrades are staggered across the fleet so coverage isn't lost during the upgrade window. Useful only with 3+ APs."
  type        = string
  default     = "disable"
}
