resource "fortios_system_dnsserver" "this" {
  name              = var.interface_name
  mode              = var.mode
  dnsfilter_profile = var.dnsfilter_profile
}
