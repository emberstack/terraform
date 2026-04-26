resource "fortios_system_externalresource" "this" {
  name         = var.name
  type         = var.type
  category     = var.category
  resource     = var.resource
  refresh_rate = var.refresh_rate
  status       = var.status
  comments     = var.comments
}
