resource "fortios_wirelesscontroller_wtp" "this" {
  wtp_id               = var.wtp_id
  name                 = var.name
  admin                = var.admin
  wtp_profile          = var.wtp_profile
  location             = var.location
  override_allowaccess = var.override_allowaccess
  # Per-AP allowaccess is only honoured when override_allowaccess is enabled;
  # otherwise the AP inherits management access from its profile and the device
  # stores nothing, so sending a value diffs forever.
  allowaccess            = var.override_allowaccess == "enable" ? var.allowaccess : null
  ip_fragment_preventing = var.ip_fragment_preventing
  mesh_bridge_enable     = var.mesh_bridge_enable

  # FortiOS auto-detects wtp-mode on AP join (normal | remote) and marks it
  # read-only afterwards; any write triggers -651 ("wtp-mode is read only").
  # `index` is likewise device-assigned and distinct per AP. Ignore drift so the
  # provider stops trying to clear them on every apply.
  lifecycle {
    ignore_changes = [wtp_mode, index]
  }
}
