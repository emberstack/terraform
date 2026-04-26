# =============================================================================
# Pattern: FortiSwitch managed-switch PORTS (per-port, via generic REST)
# =============================================================================
# The fortios provider only exposes ports as a sub-block of the whole
# managed-switch resource — which breaks at scale (positional comparison,
# hardware-field nulling, no field-level ignore). This pattern instead manages
# each port as its OWN object via the FortiOS per-port child mkey path:
#
#   /cmdb/switch-controller/managed-switch/<switch_id>/ports/<port_name>
#
# Verified that path supports GET + PUT with merge semantics — a PUT only
# touches the fields in the body, leaving hardware/computed fields alone.
#
# Each port becomes a `restful_resource` (magodo/restful provider) which gives:
#   - native two-way drift detection (reads the port each plan)
#   - body-scoped diff (only the fields we set are compared)
#   - no PowerShell, no terraform_data, no positional sub-block churn
#
# The chassis-level managed-switch leaf must set `lifecycle.ignore_changes =
# [ports]` so the two never fight over the ports sub-table.
# =============================================================================

variable "switch_id" {
  description = "Managed switch mkey (e.g. 'edge-sw-01'). Parent path segment for every port."
  type        = string
}

variable "ports" {
  description = <<-EOT
    Map of ports to manage, keyed by FortiOS port name (e.g. "port1").
    Only user-meaningful fields; everything else stays FortiLink-managed
    because the per-port PUT merges (doesn't replace) the port object.
  EOT
  type = map(object({
    status               = optional(string, "up")     # up | down (admin)
    vlan                 = optional(string)           # access/native VLAN
    allowed_vlans        = optional(list(string), []) # trunk membership
    allowed_vlans_all    = optional(string)           # enable | disable
    untagged_vlans       = optional(list(string), []) # egress-untagged VLANs
    description          = optional(string)           # user label
    port_security_policy = optional(string)           # NAC binding
    poe_status           = optional(string, "enable") # enable | disable
  }))
}
