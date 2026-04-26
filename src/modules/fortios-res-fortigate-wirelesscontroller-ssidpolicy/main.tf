resource "fortios_wirelesscontroller_ssidpolicy" "this" {
  name        = var.name
  description = var.description
  vlan        = var.vlan
}
