variable "name" {
  description = "Name of the remote certificate entry (`config vpn certificate remote`). Other objects reference the certificate by this name — e.g. `idp_cert` on a SAML server."
  type        = string
}

# Certificate input — provide exactly one of these.
variable "cert_base64" {
  description = "Bare base64 DER certificate (e.g. from Entra). The module wraps it into PEM. Mutually exclusive with var.remote."
  type        = string
  default     = ""
}

variable "remote" {
  description = "Pre-formatted PEM certificate. Used only when cert_base64 is empty."
  type        = string
  default     = ""
}

variable "range" {
  description = "Scope the certificate is installed in. One of `global` or `vdom`. Defaults to `global`."
  type        = string
  default     = "global"
}

variable "cert_source" {
  description = "Maps to the resource's `source` attribute — where FortiOS considers the certificate to have come from. One of `factory`, `user` or `bundle`. Defaults to `user`."
  type        = string
  default     = "user"
}
