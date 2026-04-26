resource "fortios_wirelesscontroller_arrpprofile" "this" {
  name                    = var.name
  comment                 = var.comment
  selection_period        = var.selection_period
  monitor_period          = var.monitor_period
  weight_managed_ap       = var.weight_managed_ap
  weight_noise_floor      = var.weight_noise_floor
  weight_dfs_channel      = var.weight_dfs_channel
  weight_channel_load     = var.weight_channel_load
  weight_rogue_ap         = var.weight_rogue_ap
  weight_spectral_rssi    = var.weight_spectral_rssi
  weight_weather_channel  = var.weight_weather_channel
  include_weather_channel = var.include_weather_channel
  include_dfs_channel     = var.include_dfs_channel
  darrp_optimize          = var.darrp_optimize

  dynamic "darrp_optimize_schedules" {
    for_each = var.darrp_optimize_schedules
    content {
      name = darrp_optimize_schedules.value
    }
  }
}
