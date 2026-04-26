resource "fortios_wirelesscontroller_widsprofile" "this" {
  name                      = var.name
  comment                   = var.comment
  sensor_mode               = var.sensor_mode
  ap_scan                   = var.ap_scan
  ap_scan_passive           = var.ap_scan_passive
  wireless_bridge           = var.wireless_bridge
  deauth_broadcast          = var.deauth_broadcast
  deauth_unknown_src_thresh = var.deauth_unknown_src_thresh
  assoc_flood_thresh        = var.assoc_flood_thresh
  assoc_flood_time          = var.assoc_flood_time
  assoc_frame_flood         = var.assoc_frame_flood
  auth_flood_thresh         = var.auth_flood_thresh
  auth_flood_time           = var.auth_flood_time
  auth_frame_flood          = var.auth_frame_flood
  weak_wep_iv               = var.weak_wep_iv
  spoofed_deauth            = var.spoofed_deauth
  eapol_logoff_flood        = var.eapol_logoff_flood
  eapol_pre_succ_flood      = var.eapol_pre_succ_flood
  eapol_pre_fail_flood      = var.eapol_pre_fail_flood
}
