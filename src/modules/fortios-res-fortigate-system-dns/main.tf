resource "fortios_system_dns" "this" {
  primary         = var.primary
  secondary       = var.secondary
  protocol        = var.protocol
  ssl_certificate = var.ssl_certificate
  dns_over_tls    = var.dns_over_tls

  dynamic "domain" {
    for_each = var.domains
    content {
      domain = domain.value
    }
  }
}
