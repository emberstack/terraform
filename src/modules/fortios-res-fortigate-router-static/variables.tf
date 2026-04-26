variable "seq_num" {
  description = "Static route sequence number (the route's mkey). Leave `null` to let FortiOS assign the next free slot; set it explicitly to pin the route to a stable table entry."
  type        = number
  default     = null
}

variable "dst" {
  description = "Destination prefix as a space-separated `<address> <netmask>` pair, e.g. `10.0.0.0 255.255.255.0`. The default `0.0.0.0 0.0.0.0` makes this a default route. Mutually exclusive with `dstaddr` on the FortiGate."
  type        = string
  default     = "0.0.0.0 0.0.0.0"
}

variable "dstaddr" {
  description = "Name of an existing firewall address or address group to use as the route destination, instead of the literal `dst` prefix. Leave `null` to route by `dst`."
  type        = string
  default     = null
}

variable "gateway" {
  description = "Next-hop gateway IP address. `0.0.0.0` means no next hop — use this for interface-only (directly connected / point-to-point) routes where `device` carries the traffic."
  type        = string
  default     = "0.0.0.0"
}

variable "device" {
  description = "Outgoing interface name for the route (e.g. `wan1`, `port1`). Leave empty when the route is steered by `sdwan_zone` instead of a specific interface."
  type        = string
  default     = ""
}

variable "sdwan_zone" {
  description = "Name of an SD-WAN zone to use as the route target. When set to a non-empty value the module emits a `sdwan_zone` block on the route; when empty or `null` no block is sent at all and the route uses `device`/`gateway`."
  type        = string
  default     = ""
}

variable "distance" {
  description = "Administrative distance for the route. Lower values win when multiple routes match the same prefix. FortiOS default for static routes is `10`."
  type        = number
  default     = 10
}

variable "priority" {
  description = "Route priority used to break ties between routes with the same prefix and distance. Lower values are preferred."
  type        = number
  default     = 1
}

variable "status" {
  description = "Whether the route is active in the routing table. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "comment" {
  description = "Free-text comment stored on the route and shown in the FortiGate GUI."
  type        = string
  default     = ""
}
