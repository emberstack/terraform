# =============================================================================
# FORTIGATE LOG DISK SETTINGS (fortios_logdisk_setting)
# =============================================================================
# `log disk setting` is a singleton: create and update both write it, and
# destroy sends `null` for every managed attribute, which FortiOS resets to
# its default. Apart from `status`, which the provider requires, and
# `roll_time`, every input defaults to `null`, so an input left unset stays
# unmanaged and keeps what the device has.
#
# `roll_time` is the exception because the provider reads it back on every
# refresh but does not mark it computed: unset, the device's value shows as a
# change to empty on every plan. It defaults to FortiOS's own `00:00`.
#
# Uploading rolled logs to an FTP server (`upload*`, `source_ip`, `interface*`,
# `vrf_select`) is not exposed.
# =============================================================================

resource "fortios_logdisk_setting" "this" {
  status      = var.status
  diskfull    = var.diskfull
  ips_archive = var.ips_archive

  full_first_warning_threshold  = var.full_first_warning_threshold
  full_second_warning_threshold = var.full_second_warning_threshold
  full_final_warning_threshold  = var.full_final_warning_threshold

  max_log_file_size = var.max_log_file_size
  roll_schedule     = var.roll_schedule
  roll_day          = var.roll_day
  roll_time         = var.roll_time

  maximum_log_age                = var.maximum_log_age
  log_quota                      = var.log_quota
  dlp_archive_quota              = var.dlp_archive_quota
  report_quota                   = var.report_quota
  max_policy_packet_capture_size = var.max_policy_packet_capture_size
}
