# Fan out the ports map → one child module instance per port. The child owns
# the single restful_resource so the per-port REST wiring lives in one place
# and this parent stays a dead-simple map dispatcher.
module "port" {
  source   = "./modules/port"
  for_each = var.ports

  switch_id            = var.switch_id
  port_name            = each.key
  status               = each.value.status
  vlan                 = each.value.vlan
  allowed_vlans        = each.value.allowed_vlans
  allowed_vlans_all    = each.value.allowed_vlans_all
  untagged_vlans       = each.value.untagged_vlans
  description          = each.value.description
  port_security_policy = each.value.port_security_policy
  poe_status           = each.value.poe_status
}
