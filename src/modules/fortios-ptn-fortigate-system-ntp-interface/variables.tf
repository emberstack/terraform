variable "interface_name" {
  description = "Name of the FortiGate interface to enable as NTP listener"
  type        = string
  nullable    = false
}

variable "insecure" {
  description = <<-EOT
    Skip TLS certificate validation on the REST calls this module makes to the
    FortiGate. Defaults to `true` because FortiGates ship with a self-signed
    certificate, which is what the fortios provider's own `insecure` setting
    exists for.

    Set to `false` once the device presents a trusted certificate. Leaving it
    `true` means the API token in the Authorization header is sent over a
    connection that is not authenticated against a trusted CA, so a
    machine-in-the-middle on the path to the FortiGate can capture it.
  EOT
  type        = bool
  default     = true
  nullable    = false
}
