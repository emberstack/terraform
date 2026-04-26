variable "name" {
  description = "Name of the NAC policy. This is the mkey — changing it replaces the policy."
  type        = string
}

variable "description" {
  description = "Free-text description stored on the NAC policy."
  type        = string
  default     = ""
}

variable "status" {
  description = "Whether the NAC policy is evaluated. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "category" {
  description = "NAC policy category. device | firewall-user | ems-tag | vulnerability | fortivoice-tag"
  type        = string
  default     = "device"
}

# ---------------------------------------------------------------------------
# Match criteria — set only what's needed. mac is the deterministic choice.
# ---------------------------------------------------------------------------
variable "mac" {
  description = "MAC address the policy matches on. The deterministic match criterion — the others depend on FortiOS device detection. Leave `null` to not match on MAC."
  type        = string
  default     = null
}

variable "hw_vendor" {
  description = "Hardware vendor of the device, as reported by FortiOS device detection. Leave `null` to not match on vendor."
  type        = string
  default     = null
}

variable "type" {
  description = "Device type reported by FortiOS device detection (the `type` match criterion, not the policy `category`). Leave `null` to not match on type."
  type        = string
  default     = null
}

variable "family" {
  description = "Device family reported by FortiOS device detection. Leave `null` to not match on family."
  type        = string
  default     = null
}

variable "os" {
  description = "Operating system reported by FortiOS device detection. Leave `null` to not match on OS."
  type        = string
  default     = null
}

variable "host" {
  description = "Hostname reported by the device. Leave `null` to not match on hostname."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Assignment — where a matched device lands.
# ---------------------------------------------------------------------------
variable "switch_fortilink" {
  description = "FortiLink interface this NAC policy belongs to."
  type        = string
}

variable "ssid_policy" {
  description = "SSID policy applied to the matched device (carries the target VLAN)."
  type        = string
}
