resource "fortios_wirelesscontroller_nacprofile" "this" {
  name            = var.name
  comment         = var.comment
  onboarding_vlan = var.onboarding_vlan
}
