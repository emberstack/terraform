resource "fortios_switchcontroller_managedswitch" "this" {
  switch_id                  = var.switch_id
  name                       = var.name
  description                = var.description
  sn                         = var.sn
  type                       = var.type
  fsw_wan1_peer              = var.fsw_wan1_peer
  fsw_wan1_admin             = var.fsw_wan1_admin
  pre_provisioned            = var.pre_provisioned
  poe_pre_standard_detection = var.poe_pre_standard_detection
  poe_detection_type         = var.poe_detection_type

  # Ports are NOT managed here. Per-port config lives in the dedicated
  # fortios-ptn-fortigate-switchcontroller-managedswitch-ports pattern (each
  # port = its own restful_resource via the per-port child mkey path). The
  # native provider's ports sub-block can't do partial/per-port management
  # without positional churn + hardware-field nulling, so this leaf owns the
  # chassis only and ignores the ports sub-table entirely.
  #
  # The other ignored fields are FortiOS-side computed read-only values the
  # provider would otherwise try to clear on every apply.
  lifecycle {
    ignore_changes = [
      ports,
      directly_connected,
      dynamically_discovered,
      max_poe_budget,
      staged_image_version,
      tdr_supported,
    ]
  }
}
