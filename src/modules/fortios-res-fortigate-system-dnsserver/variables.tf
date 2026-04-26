variable "interface_name" {
  description = "Name of an existing FortiGate interface to enable the DNS server on. This is the resource mkey — one `system dnsserver` entry per interface."
  type        = string
}

variable "mode" {
  description = "DNS server mode for the interface. One of `recursive`, `non-recursive` or `forward-only`."
  type        = string
  default     = "recursive"
}

variable "dnsfilter_profile" {
  description = "Name of the DNS filter profile applied to queries arriving on this interface. Empty string means no profile."
  type        = string
  default     = ""
}
