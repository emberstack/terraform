resource "fortios_switchcontroller_fortilinksettings" "this" {
  name            = var.name
  fortilink       = var.fortilink
  inactive_timer  = var.inactive_timer
  link_down_flush = var.link_down_flush

  dynamic "nac_ports" {
    for_each = var.nac_ports == null ? [] : [var.nac_ports]
    content {
      onboarding_vlan   = nac_ports.value.onboarding_vlan
      bounce_nac_port   = nac_ports.value.bounce_nac_port
      lan_segment       = nac_ports.value.lan_segment
      nac_lan_interface = nac_ports.value.nac_lan_interface
      parent_key        = nac_ports.value.parent_key
      member_change     = nac_ports.value.member_change

      dynamic "nac_segment_vlans" {
        for_each = nac_ports.value.nac_segment_vlans
        content {
          vlan_name = nac_segment_vlans.value
        }
      }
    }
  }
}
