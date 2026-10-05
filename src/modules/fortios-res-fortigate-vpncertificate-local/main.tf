# =============================================================================
# FORTIGATE LOCAL CERTIFICATE (fortios_vpncertificate_local)
# =============================================================================
# ACME (`acme2`) is the only enrollment method exposed, so `enroll_protocol` is
# hardcoded. FortiOS generates the key, enrolls and renews on its own, so a
# successful apply means the request was accepted, not that the certificate
# was issued: the CA's HTTP-01 check still has to reach an interface set in
# `system acme` on TCP 80.
#
# The provider never reads `private_key` or `certificate` back, so neither the
# key FortiOS generates nor the issued certificate lands in state.
#
# Changing `name` replaces the certificate. FortiOS refuses to delete one that
# is still referenced (admin server certificate, SAML, VPN), so repoint those
# first.
# =============================================================================

resource "fortios_vpncertificate_local" "this" {
  name     = var.name
  comments = var.comments

  enroll_protocol   = "acme2"
  acme_domain       = var.acme.domain
  acme_email        = var.acme.email
  acme_ca_url       = var.acme.ca_url
  acme_rsa_key_size = var.acme.rsa_key_size
  acme_renew_window = var.acme.renew_window
  acme_eab_key_id   = var.acme.eab_key_id
  acme_eab_key_hmac = var.acme_eab_key_hmac
}
