resource "fortios_system_global" "this" {
  hostname             = var.hostname
  admin_sport          = var.admin_sport
  admin_ssh_port       = var.admin_ssh_port
  admin_telnet_port    = var.admin_telnet_port
  admin_port           = var.admin_port
  admin_https_redirect = var.admin_https_redirect
  admintimeout         = var.admintimeout
  gui_theme            = var.gui_theme
  gui_local_out        = "enable"
  timezone             = var.timezone
  gui_date_time_source = var.gui_date_time_source
  gui_ipv6             = var.gui_ipv6
  gui_device_latitude  = var.gui_device_latitude
  gui_device_longitude = var.gui_device_longitude

  admin_server_cert  = var.admin_server_cert
  scim_server_cert   = var.scim_server_cert
  auth_ike_saml_port = var.auth_ike_saml_port
  remoteauthtimeout  = var.remoteauthtimeout
}

resource "fortios_system_settings" "this" {
  gui_advanced_policy           = var.system_settings.gui_advanced_policy
  gui_allow_unnamed_policy      = var.system_settings.gui_allow_unnamed_policy
  gui_implicit_policy           = var.system_settings.gui_implicit_policy
  gui_local_in_policy           = var.system_settings.gui_local_in_policy
  gui_multiple_interface_policy = var.system_settings.gui_multiple_interface_policy
  gui_policy_based_ipsec        = var.system_settings.gui_policy_based_ipsec
  gui_dynamic_routing           = var.system_settings.gui_dynamic_routing

  gui_antivirus              = var.system_settings.gui_antivirus
  gui_application_control    = var.system_settings.gui_application_control
  gui_dnsfilter              = var.system_settings.gui_dnsfilter
  gui_dos_policy             = var.system_settings.gui_dos_policy
  gui_file_filter            = var.system_settings.gui_file_filter
  gui_ips                    = var.system_settings.gui_ips
  gui_security_profile_group = var.system_settings.gui_security_profile_group
  gui_voip_profile           = var.system_settings.gui_voip_profile
  gui_waf_profile            = var.system_settings.gui_waf_profile
  gui_webfilter              = var.system_settings.gui_webfilter

  gui_dns_database     = var.system_settings.gui_dns_database
  gui_dhcp_advanced    = var.system_settings.gui_dhcp_advanced
  gui_load_balance     = var.system_settings.gui_load_balance
  gui_multicast_policy = var.system_settings.gui_multicast_policy
  gui_traffic_shaping  = var.system_settings.gui_traffic_shaping
  gui_explicit_proxy   = var.system_settings.gui_explicit_proxy

  gui_vpn    = var.system_settings.gui_vpn
  gui_sslvpn = var.system_settings.gui_sslvpn
  gui_ztna   = var.system_settings.gui_ztna

  gui_wireless_controller      = var.system_settings.gui_wireless_controller
  gui_ap_profile               = var.system_settings.gui_ap_profile
  gui_fortiap_split_tunneling  = var.system_settings.gui_fortiap_split_tunneling
  gui_switch_controller        = var.system_settings.gui_switch_controller
  gui_fortiextender_controller = var.system_settings.gui_fortiextender_controller

  gui_email_collection = var.system_settings.gui_email_collection
  gui_object_colors    = var.system_settings.gui_object_colors
}

resource "fortios_system_ntp" "this" {
  ntpsync      = var.ntp.ntpsync
  server_mode  = var.ntp.server_mode
  syncinterval = var.ntp.syncinterval

  dynamic "interface" {
    for_each = var.ntp.interfaces
    content {
      interface_name = interface.value
    }
  }

  lifecycle {
    ignore_changes = [ntpserver, interface]
  }
}
