variable "route_server_resource_id" {
  type        = string
  description = "Resource ID of the route server to peer with — the parent module's `resource_id`, a `Microsoft.Network/virtualHubs` resource."
  nullable    = false

  validation {
    condition     = can(regex("(?i)^/subscriptions/[^/]+/resourceGroups/[^/]+/providers/Microsoft\\.Network/virtualHubs/[^/]+$", var.route_server_resource_id))
    error_message = "route_server_resource_id must be a Microsoft.Network/virtualHubs resource ID."
  }
}

variable "name" {
  type        = string
  description = "Name of the BGP connection. It identifies the peering only and need not match the NVA's name."
  nullable    = false

  validation {
    condition     = can(regex("^[a-zA-Z0-9]([a-zA-Z0-9._-]{0,78}[a-zA-Z0-9_])?$", var.name))
    error_message = "name must be 1-80 characters of letters, digits, underscores, periods and hyphens, starting with a letter or digit and ending with a letter, digit or underscore."
  }
}

variable "peer_asn" {
  type        = number
  description = "ASN of the peer NVA, public or private. It must differ from the route server's own (65515)."
  nullable    = false

  validation {
    condition     = floor(var.peer_asn) == var.peer_asn && var.peer_asn >= 1 && var.peer_asn <= 4294967294
    error_message = "peer_asn must be a whole number from 1 to 4294967294."
  }

  # The reserved ASNs listed in the Azure Route Server FAQ ("What Autonomous
  # System Numbers (ASNs) can I use?"). 65515 is also the route server's own.
  validation {
    condition = !(
      contains([8074, 8075, 12076, 23456, 65515, 65517, 65518, 65519, 65520], var.peer_asn) ||
      (var.peer_asn >= 64496 && var.peer_asn <= 64511) ||
      (var.peer_asn >= 65535 && var.peer_asn <= 65551)
    )
    error_message = "peer_asn is reserved by Azure (8074, 8075, 12076, 65515, 65517-65520) or IANA (23456, 64496-64511, 65535-65551)."
  }
}

variable "peer_ip" {
  type        = string
  description = "Private IPv4 address of the peer NVA."
  nullable    = false

  validation {
    condition     = can(cidrhost("${var.peer_ip}/32", 0)) && can(regex("^[0-9.]+$", var.peer_ip))
    error_message = "peer_ip must be an IPv4 address."
  }
}
