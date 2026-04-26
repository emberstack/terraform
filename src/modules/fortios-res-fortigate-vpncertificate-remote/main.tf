locals {
  # IdPs (Entra, etc.) commonly hand out a bare base64 DER blob with no PEM
  # armor. Wrap it into PEM with 64-char lines. If cert_base64 is empty, fall
  # back to a pre-formatted PEM passed via var.remote.
  _pem_lines = var.cert_base64 != "" ? join("\n", [
    for i in range(0, ceil(length(var.cert_base64) / 64)) : substr(var.cert_base64, i * 64, 64)
  ]) : ""

  # sensitive() on BOTH branches — otherwise the resource attribute is redacted
  # when the cert arrives via cert_base64 and printed in full when it arrives
  # via var.remote, which is a confusing inconsistency in plan output.
  _remote = var.cert_base64 != "" ? sensitive("-----BEGIN CERTIFICATE-----\n${local._pem_lines}\n-----END CERTIFICATE-----") : sensitive(var.remote)
}

resource "fortios_vpncertificate_remote" "this" {
  name   = var.name
  remote = local._remote
  range  = var.range
  source = var.cert_source

  update_if_exist = true
}
