variable "switch_id" {
  description = "Managed switch mkey (e.g. `edge-sw-01`). Forms the parent segment of the per-port REST path `/cmdb/switch-controller/managed-switch/<switch_id>/ports/<port_name>`."
  type        = string
}

variable "port_name" {
  description = "FortiOS port name (e.g. `port1`). Used as the child mkey in the per-port REST path; must match a port that already exists on the switch, since this module adopts physical ports rather than creating them."
  type        = string
}

variable "status" {
  description = "Administrative state of the port. One of `up` or `down`. Always sent in the request body — unlike the other fields, it has no null short-circuit, so it is written on every apply."
  type        = string
  default     = "up"
}

variable "vlan" {
  description = "Access (native) VLAN name for the port. Sent as `vlan` only when non-null; leaving it null omits the field so FortiLink-managed state is preserved. Note this is also the value the port is reverted to on destroy (`_default`), since physical ports cannot be deleted."
  type        = string
  default     = null
}

variable "allowed_vlans" {
  description = "VLAN names allowed on the port as tagged/trunk members. Sent as `allowed-vlans` (a list of `{ vlan-name = ... }` objects) only when the list is non-empty; an empty list omits the field rather than clearing existing membership."
  type        = list(string)
  default     = []
}

variable "allowed_vlans_all" {
  description = "Whether the port trunks all VLANs, overriding `allowed_vlans`. One of `enable` or `disable`. Sent as `allowed-vlans-all` only when non-null."
  type        = string
  default     = null
}

variable "untagged_vlans" {
  description = "VLAN names transmitted untagged on egress. Sent as `untagged-vlans` (a list of `{ vlan-name = ... }` objects) only when the list is non-empty; an empty list omits the field rather than clearing existing membership."
  type        = list(string)
  default     = []
}

variable "description" {
  description = "Free-text label stored on the port. Sent only when non-null."
  type        = string
  default     = null
}

variable "port_security_policy" {
  description = "Name of an existing switch-controller port-security (NAC/802.1X) policy to bind to the port. Sent as `port-security-policy` only when non-null."
  type        = string
  default     = null
}

variable "poe_status" {
  description = "Whether PoE is delivered on the port. One of `enable` or `disable`. Sent as `poe-status` only when non-null; has no effect on non-PoE hardware."
  type        = string
  default     = "enable"
}
