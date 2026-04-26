resource "fortios_wirelesscontroller_setting" "this" {
  country              = var.country
  duplicate_ssid       = var.duplicate_ssid
  fapc_compatibility   = var.fapc_compatibility
  wfa_compatibility    = var.wfa_compatibility
  phishing_ssid_detect = var.phishing_ssid_detect
  fake_ssid_action     = var.fake_ssid_action
  device_weight        = var.device_weight
  device_holdoff       = var.device_holdoff
  device_idle          = var.device_idle

  darrp_optimize                      = var.darrp_optimize
  firmware_provision_on_authorization = var.firmware_provision_on_authorization
  rolling_wtp_upgrade                 = var.rolling_wtp_upgrade

  dynamic "darrp_optimize_schedules" {
    for_each = var.darrp_optimize_schedules
    content {
      name = darrp_optimize_schedules.value
    }
  }
}
