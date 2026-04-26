# =============================================================================
# switch-controller/managed-switch — a FortiSwitch managed by this FortiGate.
# =============================================================================
# Shallow scope: chassis identity + uplink + PoE detection. Per-port config,
# STP, IGMP/DHCP snooping, 802.1x are deliberately NOT exposed here — they
# either auto-tune via FortiLink, are handled by FortiGate-side NAC policies,
# or warrant a separate purpose-built leaf if locked down per-switch.
# =============================================================================

variable "switch_id" {
  description = "Switch mkey. Friendly identifier shown in the GUI list (e.g. 'core-sw-01'). Distinct from `sn` (the actual serial)."
  type        = string
}

variable "name" {
  description = "Optional alternate name for the switch. Box default is empty; switch_id is usually enough."
  type        = string
  default     = ""
}

variable "description" {
  description = "Free-text description shown in the GUI."
  type        = string
  default     = ""
}

variable "sn" {
  description = "Physical serial number of the FortiSwitch (e.g. SM24GFS123456789)."
  type        = string
}

variable "type" {
  description = "'physical' for an actual switch, 'virtual' for a software switch (rare)."
  type        = string
  default     = "physical"
}

variable "fsw_wan1_peer" {
  description = "FortiGate interface name the switch uplinks to. Almost always 'fortilink'."
  type        = string
  default     = "fortilink"
}

variable "fsw_wan1_admin" {
  description = "Whether the FortiLink uplink is administratively enabled."
  type        = string
  default     = "enable"
}

variable "pre_provisioned" {
  description = "When >0, this slot is reserved for a not-yet-joined switch. 0 means the switch must already be discovered."
  type        = number
  default     = 0
}

variable "poe_pre_standard_detection" {
  description = "'enable' for pre-802.3af devices (legacy PoE). 'disable' for modern devices only."
  type        = string
  default     = "disable"
}

variable "poe_detection_type" {
  description = "PoE detection algorithm. 1 = legacy/passive, 2 = IEEE-standard 4-point (most modern devices). Match chassis-default."
  type        = number
  default     = 2
}
