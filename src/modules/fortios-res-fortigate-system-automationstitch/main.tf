resource "fortios_system_automationstitch" "this" {
  name        = var.name
  description = var.description
  status      = var.status
  trigger     = var.trigger

  dynamic "actions" {
    for_each = var.actions
    content {
      id     = actions.key + 1 # 1-based sequence
      action = actions.value
    }
  }
}
