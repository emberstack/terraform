resource "fortios_firewallschedule_recurring" "this" {
  name          = var.name
  start         = var.start
  end           = var.end
  day           = var.day
  color         = var.color
  fabric_object = var.fabric_object
}
