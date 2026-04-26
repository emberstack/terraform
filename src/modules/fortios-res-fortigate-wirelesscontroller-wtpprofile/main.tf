resource "fortios_wirelesscontroller_wtpprofile" "this" {
  update_if_exist = var.update_if_exist

  name               = var.name
  comment            = var.comment
  ap_country         = var.ap_country
  allowaccess        = var.allowaccess
  ap_handoff         = var.ap_handoff
  frequency_handoff  = var.frequency_handoff
  handoff_sta_thresh = var.handoff_sta_thresh
  wan_port_mode      = var.wan_port_mode
  led_state          = var.led_state
  poe_mode           = var.poe_mode

  platform {
    type   = var.platform.type
    mode   = var.platform.mode
    ddscan = var.platform.ddscan
  }

  dynamic "lan" {
    for_each = var.lan == null ? [] : [var.lan]
    content {
      port_mode  = lan.value.port_mode
      port_ssid  = lan.value.port_ssid
      port1_mode = lan.value.port1_mode
      port1_ssid = lan.value.port1_ssid
    }
  }

  # auto_power_level / darrp / short_guard_interval are transmit-side settings
  # that only apply to serving radios. FortiOS forces them off on monitor and
  # sniffer radios, so sending the "enable" defaults there diffs forever.
  dynamic "radio_1" {
    for_each = var.radio_1 == null ? [] : [var.radio_1]
    content {
      mode                 = radio_1.value.mode
      band                 = radio_1.value.band
      channel_bonding      = radio_1.value.channel_bonding
      power_level          = radio_1.value.power_level
      auto_power_level     = radio_1.value.mode == "ap" ? radio_1.value.auto_power_level : null
      auto_power_low       = radio_1.value.auto_power_low
      auto_power_high      = radio_1.value.auto_power_high
      darrp                = radio_1.value.mode == "ap" ? radio_1.value.darrp : null
      arrp_profile         = radio_1.value.arrp_profile
      short_guard_interval = radio_1.value.mode == "ap" ? radio_1.value.short_guard_interval : null
      vap_all              = radio_1.value.vap_all
      wids_profile         = radio_1.value.wids_profile
      protection_mode      = radio_1.value.protection_mode

      dynamic "channel" {
        for_each = radio_1.value.channel
        content {
          chan = tostring(channel.value)
        }
      }

      dynamic "vaps" {
        for_each = radio_1.value.vaps
        content {
          name = vaps.value
        }
      }
    }
  }

  dynamic "radio_2" {
    for_each = var.radio_2 == null ? [] : [var.radio_2]
    content {
      mode                 = radio_2.value.mode
      band                 = radio_2.value.band
      channel_bonding      = radio_2.value.channel_bonding
      power_level          = radio_2.value.power_level
      auto_power_level     = radio_2.value.mode == "ap" ? radio_2.value.auto_power_level : null
      auto_power_low       = radio_2.value.auto_power_low
      auto_power_high      = radio_2.value.auto_power_high
      darrp                = radio_2.value.mode == "ap" ? radio_2.value.darrp : null
      arrp_profile         = radio_2.value.arrp_profile
      short_guard_interval = radio_2.value.mode == "ap" ? radio_2.value.short_guard_interval : null
      vap_all              = radio_2.value.vap_all
      wids_profile         = radio_2.value.wids_profile
      protection_mode      = radio_2.value.protection_mode

      dynamic "channel" {
        for_each = radio_2.value.channel
        content {
          chan = tostring(channel.value)
        }
      }

      dynamic "vaps" {
        for_each = radio_2.value.vaps
        content {
          name = vaps.value
        }
      }
    }
  }

  dynamic "radio_3" {
    for_each = var.radio_3 == null ? [] : [var.radio_3]
    content {
      mode                 = radio_3.value.mode
      band                 = radio_3.value.band
      channel_bonding      = radio_3.value.channel_bonding
      power_level          = radio_3.value.power_level
      auto_power_level     = radio_3.value.mode == "ap" ? radio_3.value.auto_power_level : null
      auto_power_low       = radio_3.value.auto_power_low
      auto_power_high      = radio_3.value.auto_power_high
      darrp                = radio_3.value.mode == "ap" ? radio_3.value.darrp : null
      arrp_profile         = radio_3.value.arrp_profile
      short_guard_interval = radio_3.value.mode == "ap" ? radio_3.value.short_guard_interval : null
      vap_all              = radio_3.value.vap_all
      wids_profile         = radio_3.value.wids_profile
      protection_mode      = radio_3.value.protection_mode

      dynamic "channel" {
        for_each = radio_3.value.channel
        content {
          chan = tostring(channel.value)
        }
      }

      dynamic "vaps" {
        for_each = radio_3.value.vaps
        content {
          name = vaps.value
        }
      }
    }
  }

  dynamic "radio_4" {
    for_each = var.radio_4 == null ? [] : [var.radio_4]
    content {
      mode                 = radio_4.value.mode
      band                 = radio_4.value.band
      channel_bonding      = radio_4.value.channel_bonding
      power_level          = radio_4.value.power_level
      auto_power_level     = radio_4.value.mode == "ap" ? radio_4.value.auto_power_level : null
      auto_power_low       = radio_4.value.auto_power_low
      auto_power_high      = radio_4.value.auto_power_high
      darrp                = radio_4.value.mode == "ap" ? radio_4.value.darrp : null
      arrp_profile         = radio_4.value.arrp_profile
      short_guard_interval = radio_4.value.mode == "ap" ? radio_4.value.short_guard_interval : null
      vap_all              = radio_4.value.vap_all
      wids_profile         = radio_4.value.wids_profile
      protection_mode      = radio_4.value.protection_mode

      dynamic "channel" {
        for_each = radio_4.value.channel
        content {
          chan = tostring(channel.value)
        }
      }

      dynamic "vaps" {
        for_each = radio_4.value.vaps
        content {
          name = vaps.value
        }
      }
    }
  }

  # FortiOS marks `radio_id` as "info only" — provider re-reads it from box and
  # would otherwise try to clear it on every apply. Only radio_1/radio_2 expose
  # the attribute in the fortios provider schema; radio_3/radio_4 don't have it.
  lifecycle {
    ignore_changes = [
      radio_1[0].radio_id,
      radio_2[0].radio_id,
    ]
  }
}
