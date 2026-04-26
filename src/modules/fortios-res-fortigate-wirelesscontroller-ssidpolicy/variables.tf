variable "name" {
  description = "Name of the SSID policy. This is the FortiOS mkey — changing it replaces the object. Referenced by name from a VAP's SSID policy assignment."
  type        = string
}

variable "description" {
  description = "Free-text comment stored on the SSID policy object. Cosmetic only."
  type        = string
  default     = ""
}

variable "vlan" {
  description = "VLAN interface name a matched device is assigned to."
  type        = string
}
