variable "name" {
  description = "Custom service name (`name` mkey). This is the value firewall policies reference in their `service` list."
  type        = string
}

variable "category" {
  description = "Service category the object is filed under in the GUI service list, e.g. `Network Services`, `Web Access`, `File Access`, `Email`, `Remote Access`, `Tunneling`, `VoIP, Messaging & Other Applications`, `Web Proxy`, `General`. The category must already exist on the device."
  type        = string
  default     = "Network Services"
}

variable "protocol" {
  description = "Protocol family the service matches. One of `TCP/UDP/UDP-Lite/SCTP`, `ICMP`, `ICMP6`, `IP`, `HTTP`, `FTP`, `CONNECT`, `SOCKS-TCP`, `SOCKS-UDP` or `ALL`. The `*_portrange` inputs only apply to `TCP/UDP/UDP-Lite/SCTP`."
  type        = string
  default     = "TCP/UDP/UDP-Lite/SCTP"
}

variable "tcp_portrange" {
  description = "TCP port ranges, one entry per range. Joined with spaces into the single FortiOS `tcp-portrange` string; sent as null when empty so the attribute is omitted. Each entry is `<dst>`, `<dst-low>-<dst-high>`, or `<dst>:<src-low>-<src-high>` to also constrain the source port."
  type        = list(string)
  default     = []
}

variable "udp_portrange" {
  description = "UDP port ranges, one entry per range. Joined with spaces into the single FortiOS `udp-portrange` string; sent as null when empty. Same entry syntax as `tcp_portrange`."
  type        = list(string)
  default     = []
}

variable "sctp_portrange" {
  description = "SCTP port ranges, one entry per range. Joined with spaces into the single FortiOS `sctp-portrange` string; sent as null when empty. Same entry syntax as `tcp_portrange`."
  type        = list(string)
  default     = []
}

variable "color" {
  description = "GUI colour index for the service icon. `0` uses the FortiOS default colour."
  type        = number
  default     = 0
}

variable "comment" {
  description = "Free-text comment stored on the service object."
  type        = string
  default     = ""
}

# "0" = inherit the global session-ttl (custom values are 300-2764800); matches
# the FortiOS device default so unset services don't perpetually diff.
variable "session_ttl" {
  description = "Per-service session timeout in seconds, as a string. `\"0\"` inherits the global session-ttl and is the FortiOS device default; explicit values must be in the range `300`-`2764800`. The default avoids a perpetual diff because the provider reads back `\"0\"` rather than null."
  type        = string
  default     = "0"
}
