resource "fortios_user_nacpolicy" "this" {
  name             = var.name
  description      = var.description
  status           = var.status
  category         = var.category
  mac              = var.mac
  hw_vendor        = var.hw_vendor
  type             = var.type
  family           = var.family
  os               = var.os
  host             = var.host
  switch_fortilink = var.switch_fortilink
  ssid_policy      = var.ssid_policy
}
