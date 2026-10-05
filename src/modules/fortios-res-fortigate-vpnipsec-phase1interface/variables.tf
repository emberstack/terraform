variable "name" {
  description = "Phase1 interface name, at most 15 characters. It is also the name of the tunnel interface that phase2s, routes and policies reference."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 15
    error_message = "name must be 1 to 15 characters."
  }
}

variable "interface" {
  description = "Local interface the tunnel terminates on, e.g. `port1`."
  type        = string
  nullable    = false

  validation {
    condition     = length(var.interface) > 0
    error_message = "interface must not be empty."
  }
}

variable "type" {
  description = "Remote gateway type: `static` (fixed `remote_gw`), `ddns` (`remotegw_ddns`) or `dynamic` (dial-up peers). `null` leaves it unmanaged; FortiOS defaults to `static`."
  type        = string
  default     = null

  validation {
    condition     = var.type == null || contains(["static", "dynamic", "ddns"], var.type)
    error_message = "type must be static, dynamic or ddns."
  }
}

variable "comments" {
  description = "Free-text comment, at most 255 characters. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.comments == null || length(var.comments) <= 255
    error_message = "comments must be at most 255 characters."
  }
}

# -----------------------------------------------------------------------------
# Gateways
# -----------------------------------------------------------------------------

variable "ip_version" {
  description = "IP version of the tunnel: `4` or `6`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.ip_version == null || contains(["4", "6"], var.ip_version)
    error_message = "ip_version must be 4 or 6."
  }
}

variable "local_gw" {
  description = "Local gateway IPv4 address, when `interface` has several. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "remote_gw" {
  description = "Remote gateway IPv4 address, for `type = \"static\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "remotegw_ddns" {
  description = "Remote gateway domain name, for `type = \"ddns\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# IKE
# -----------------------------------------------------------------------------

variable "ike_version" {
  description = "IKE version: `1` or `2`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.ike_version == null || contains(["1", "2"], var.ike_version)
    error_message = "ike_version must be 1 or 2."
  }
}

variable "mode" {
  description = "IKEv1 exchange mode: `main` or `aggressive`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.mode == null || contains(["main", "aggressive"], var.mode)
    error_message = "mode must be main or aggressive."
  }
}

variable "proposal" {
  description = "Phase1 proposals, space-separated, e.g. `aes256gcm-prfsha384 chacha20poly1305-prfsha256`. Required by the provider."
  type        = string
  nullable    = false

  validation {
    condition     = length(trimspace(var.proposal)) > 0
    error_message = "proposal must not be empty."
  }
}

variable "dhgrp" {
  description = "Diffie-Hellman groups, space-separated, e.g. `20 21`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.dhgrp == null || alltrue([for group in split(" ", var.dhgrp) : contains(["1", "2", "5", "14", "15", "16", "17", "18", "19", "20", "21", "27", "28", "29", "30", "31", "32"], group)])
    error_message = "dhgrp must be space-separated groups from 1, 2, 5, 14-21 and 27-32."
  }
}

variable "keylife" {
  description = "Phase1 key lifetime in seconds (120-172800). `null` leaves it unmanaged; FortiOS defaults to 86400."
  type        = number
  default     = null

  validation {
    condition     = var.keylife == null || (var.keylife >= 120 && var.keylife <= 172800)
    error_message = "keylife must be between 120 and 172800."
  }
}

variable "negotiate_timeout" {
  description = "IKE SA negotiation timeout in seconds (1-300). Dial-up clients that sign in through SAML need time for the browser round trip. `null` leaves it unmanaged; FortiOS defaults to 30."
  type        = number
  default     = null

  validation {
    condition     = var.negotiate_timeout == null || (var.negotiate_timeout >= 1 && var.negotiate_timeout <= 300)
    error_message = "negotiate_timeout must be between 1 and 300."
  }
}

variable "nattraversal" {
  description = "NAT traversal: `enable`, `disable` or `forced`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.nattraversal == null || contains(["enable", "disable", "forced"], var.nattraversal)
    error_message = "nattraversal must be enable, disable or forced."
  }
}

variable "transport" {
  description = "IKE transport, e.g. `udp`, `tcp` or `auto`. Accepted values depend on the FortiOS version, so they are not validated. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "localid" {
  description = "Local ID sent to the peer. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "localid_type" {
  description = "Local ID type: `auto`, `fqdn`, `user-fqdn`, `keyid`, `address` or `asn1dn`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.localid_type == null || contains(["auto", "fqdn", "user-fqdn", "keyid", "address", "asn1dn"], var.localid_type)
    error_message = "localid_type must be auto, fqdn, user-fqdn, keyid, address or asn1dn."
  }
}

# -----------------------------------------------------------------------------
# Dead peer detection and idle timeout
# -----------------------------------------------------------------------------

variable "dpd" {
  description = "Dead peer detection: `disable`, `on-idle` or `on-demand`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.dpd == null || contains(["disable", "on-idle", "on-demand"], var.dpd)
    error_message = "dpd must be disable, on-idle or on-demand."
  }
}

variable "dpd_retrycount" {
  description = "DPD retries before the peer is declared dead (1-10). `null` leaves it unmanaged; FortiOS defaults to 3."
  type        = number
  default     = null

  validation {
    condition     = var.dpd_retrycount == null || (var.dpd_retrycount >= 1 && var.dpd_retrycount <= 10)
    error_message = "dpd_retrycount must be between 1 and 10."
  }
}

variable "dpd_retryinterval" {
  description = "DPD retry interval, as FortiOS takes it: seconds, optionally followed by milliseconds (e.g. `20`, or `5 500`). `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "idle_timeout" {
  description = "Tear the tunnel down after a period without traffic. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.idle_timeout == null || contains(["enable", "disable"], var.idle_timeout)
    error_message = "idle_timeout must be enable or disable."
  }
}

variable "idle_timeoutinterval" {
  description = "Idle timeout in minutes (5-43200), used when `idle_timeout` is `enable`. `null` leaves it unmanaged; FortiOS defaults to 15."
  type        = number
  default     = null

  validation {
    condition     = var.idle_timeoutinterval == null || (var.idle_timeoutinterval >= 5 && var.idle_timeoutinterval <= 43200)
    error_message = "idle_timeoutinterval must be between 5 and 43200."
  }
}

# -----------------------------------------------------------------------------
# Authentication
# -----------------------------------------------------------------------------

variable "authmethod" {
  description = "How the gateways authenticate: `psk` or `signature` (certificates). `null` leaves it unmanaged; FortiOS defaults to `psk`."
  type        = string
  default     = null

  validation {
    condition     = var.authmethod == null || contains(["psk", "signature"], var.authmethod)
    error_message = "authmethod must be psk or signature."
  }
}

variable "psksecret" {
  description = "Pre-shared key, as an ASCII string or hexadecimal with a leading `0x`. FortiOS never returns it, so a key changed on the device is not detected. `null` sends none."
  type        = string
  default     = null
  sensitive   = true
}

variable "certificates" {
  description = "Local certificates presented with `authmethod = \"signature\"`. The complete list when set. Empty from the start leaves the sub-table unmanaged; emptying a list that was set clears it on the device."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "peertype" {
  description = "Which peer IDs to accept: `any`, `one` (`peerid`), `dialup` (a user group), `peer` (`peer` certificate) or `peergrp` (`peergrp`). `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.peertype == null || contains(["any", "one", "dialup", "peer", "peergrp"], var.peertype)
    error_message = "peertype must be any, one, dialup, peer or peergrp."
  }
}

variable "peerid" {
  description = "Peer ID to accept, with `peertype = \"one\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "peer" {
  description = "Peer certificate to accept, with `peertype = \"peer\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "peergrp" {
  description = "Peer certificate group to accept, with `peertype = \"peergrp\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "eap" {
  description = "IKEv2 EAP authentication of the user, e.g. EAP-SAML through the interface's `ike_saml_server`. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.eap == null || contains(["enable", "disable"], var.eap)
    error_message = "eap must be enable or disable."
  }
}

variable "eap_identity" {
  description = "How the EAP identity is obtained: `use-id-payload` or `send-request`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.eap_identity == null || contains(["use-id-payload", "send-request"], var.eap_identity)
    error_message = "eap_identity must be use-id-payload or send-request."
  }
}

variable "authusrgrp" {
  description = "User group the phase1 authenticates users against. Not needed when firewall policies do the group matching instead. `null` leaves it unmanaged, so it does not clear a group already set on the device."
  type        = string
  default     = null
}

# -----------------------------------------------------------------------------
# Mode-cfg (client configuration for dial-up)
# -----------------------------------------------------------------------------

variable "mode_cfg" {
  description = "Hand client configuration (address, DNS, split networks) to dial-up peers. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.mode_cfg == null || contains(["enable", "disable"], var.mode_cfg)
    error_message = "mode_cfg must be enable or disable."
  }
}

variable "assign_ip" {
  description = "Assign clients an address through mode-cfg. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.assign_ip == null || contains(["enable", "disable"], var.assign_ip)
    error_message = "assign_ip must be enable or disable."
  }
}

variable "assign_ip_from" {
  description = "Where client addresses come from: `range` (`ipv4_start_ip`-`ipv4_end_ip`), `name` (`ipv4_name`), `usrgrp` or `dhcp`. `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.assign_ip_from == null || contains(["range", "usrgrp", "dhcp", "name"], var.assign_ip_from)
    error_message = "assign_ip_from must be range, usrgrp, dhcp or name."
  }
}

variable "ipv4_start_ip" {
  description = "First client address, with `assign_ip_from = \"range\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_end_ip" {
  description = "Last client address, with `assign_ip_from = \"range\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_netmask" {
  description = "Netmask handed to clients, dotted decimal. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_name" {
  description = "Firewall address or group to take client addresses from, with `assign_ip_from = \"name\"`. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_dns_server1" {
  description = "First DNS server handed to clients. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_dns_server2" {
  description = "Second DNS server handed to clients. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_dns_server3" {
  description = "Third DNS server handed to clients. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_split_include" {
  description = "Firewall address or group of the networks clients route through the tunnel (split tunnelling). `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "ipv4_split_exclude" {
  description = "Firewall address or group of the networks clients keep off the tunnel. `null` leaves it unmanaged."
  type        = string
  default     = null
}

variable "save_password" {
  description = "Let VPN clients save the user's credentials. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.save_password == null || contains(["enable", "disable"], var.save_password)
    error_message = "save_password must be enable or disable."
  }
}

variable "client_auto_negotiate" {
  description = "Let VPN clients bring the tunnel up without traffic. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.client_auto_negotiate == null || contains(["enable", "disable"], var.client_auto_negotiate)
    error_message = "client_auto_negotiate must be enable or disable."
  }
}

variable "client_keep_alive" {
  description = "Let VPN clients keep the tunnel up without traffic. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.client_keep_alive == null || contains(["enable", "disable"], var.client_keep_alive)
    error_message = "client_keep_alive must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Tunnel interface behaviour
# -----------------------------------------------------------------------------

variable "auto_negotiate" {
  description = "Bring the IKE SA up without waiting for traffic. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.auto_negotiate == null || contains(["enable", "disable"], var.auto_negotiate)
    error_message = "auto_negotiate must be enable or disable."
  }
}

variable "add_route" {
  description = "Add a route to each peer's destination selector, e.g. a /32 per connected dial-up client. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.add_route == null || contains(["enable", "disable"], var.add_route)
    error_message = "add_route must be enable or disable."
  }
}

variable "net_device" {
  description = "Create a kernel device per dial-up peer instead of sharing one interface. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.net_device == null || contains(["enable", "disable"], var.net_device)
    error_message = "net_device must be enable or disable."
  }
}

variable "exchange_interface_ip" {
  description = "Exchange tunnel interface addresses with the peer. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.exchange_interface_ip == null || contains(["enable", "disable"], var.exchange_interface_ip)
    error_message = "exchange_interface_ip must be enable or disable."
  }
}

variable "network_overlay" {
  description = "Use `network_id` to tell apart several tunnels between the same gateways, or several dial-up tunnels on one interface. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.network_overlay == null || contains(["enable", "disable"], var.network_overlay)
    error_message = "network_overlay must be enable or disable."
  }
}

variable "network_id" {
  description = "Network ID (0-255), used with `network_overlay = \"enable\"`. Both ends must match. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.network_id == null || (var.network_id >= 0 && var.network_id <= 255)
    error_message = "network_id must be between 0 and 255."
  }
}

variable "wizard_type" {
  description = "VPN wizard template the GUI shows the tunnel as, e.g. `dialup-forticlient` or `custom`. It only affects how the GUI presents the tunnel. Not validated. `null` leaves it unmanaged."
  type        = string
  default     = null
}
