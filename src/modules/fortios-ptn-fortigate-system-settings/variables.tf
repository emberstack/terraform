variable "hostname" {
  description = "Device hostname, shown in the GUI, CLI prompt and used in syslog/FortiAnalyzer identification."
  type        = string
}

# --- system_global scalars: nullable → only managed when the caller passes them ---

variable "admin_sport" {
  description = "TCP port for HTTPS administrative access. Leave `null` to let the device keep its current value unmanaged."
  type        = number
  default     = null
}

variable "admin_ssh_port" {
  description = "TCP port for SSH administrative access. Leave `null` to leave it unmanaged."
  type        = number
  default     = null
}

variable "admin_telnet_port" {
  description = "TCP port for Telnet administrative access. Leave `null` to leave it unmanaged."
  type        = number
  default     = null
}

variable "admin_port" {
  description = "TCP port for plain HTTP administrative access — the port `admin_https_redirect` redirects from. Leave `null` to leave it unmanaged."
  type        = number
  default     = null
}

variable "admin_https_redirect" {
  description = "Redirect HTTP admin access to HTTPS. One of `enable` or `disable`. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "admintimeout" {
  description = "Idle timeout for administrator sessions, in minutes. Leave `null` to leave it unmanaged."
  type        = number
  default     = null
}

variable "gui_theme" {
  description = "Colour theme of the administrative GUI (e.g. `jade`, `neutrino`, `mariner`, `graphite`). Cosmetic only. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "timezone" {
  description = "Device timezone, given as the FortiOS numeric timezone index in string form (e.g. `\"04\"`), not an IANA name. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "gui_date_time_source" {
  description = "Whose clock the GUI renders timestamps against. One of `system` (the FortiGate) or `browser`. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "gui_ipv6" {
  description = "Show IPv6 configuration pages in the GUI. One of `enable` or `disable`. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "gui_device_latitude" {
  description = "Latitude reported for the device, used to place it on GUI/FortiManager maps. String, not a number. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "gui_device_longitude" {
  description = "Longitude reported for the device, used to place it on GUI/FortiManager maps. String, not a number. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

# --- Certificates / auth (managed-cert family; null = unmanaged) ---

variable "admin_server_cert" {
  description = "Name of an existing local certificate to serve for HTTPS admin access (e.g. `Fortinet_Factory`, or an imported cert). The certificate must already exist on the device — this module does not create it. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "scim_server_cert" {
  description = "Name of an existing local certificate used by the SCIM server. Must already exist on the device. Leave `null` to leave it unmanaged."
  type        = string
  default     = null
}

variable "auth_ike_saml_port" {
  description = "TCP port the device listens on for IKE SAML authentication. Leave `null` to leave it unmanaged."
  type        = number
  default     = null
}

variable "remoteauthtimeout" {
  description = "How long, in seconds, to wait for a remote authentication server (RADIUS/LDAP/SAML) to respond before giving up. Leave `null` to leave it unmanaged."
  type        = number
  default     = null
}

# --- system_settings: nullable fields → only managed when passed ---

variable "system_settings" {
  description = <<-EOT
    VDOM-level `system settings` flags, almost all of which toggle GUI feature
    visibility rather than changing packet handling. Every field is a FortiOS
    `enable`/`disable` string, not a bool, and every field is optional — an
    omitted field is left `null` and therefore unmanaged, so the device keeps
    whatever it already has. The default `{}` manages none of them.

    Policy pages: `gui_advanced_policy`, `gui_allow_unnamed_policy`,
    `gui_implicit_policy`, `gui_local_in_policy`,
    `gui_multiple_interface_policy`, `gui_policy_based_ipsec`,
    `gui_dynamic_routing`.

    Security profile pages: `gui_antivirus`, `gui_application_control`,
    `gui_dnsfilter`, `gui_dos_policy`, `gui_file_filter`, `gui_ips`,
    `gui_security_profile_group`, `gui_voip_profile`, `gui_waf_profile`,
    `gui_webfilter`.

    Network service pages: `gui_dns_database`, `gui_dhcp_advanced`,
    `gui_load_balance`, `gui_multicast_policy`, `gui_traffic_shaping`,
    `gui_explicit_proxy`.

    VPN pages: `gui_vpn`, `gui_sslvpn`, `gui_ztna`.

    Fabric controller pages: `gui_wireless_controller`, `gui_ap_profile`,
    `gui_fortiap_split_tunneling`, `gui_switch_controller`,
    `gui_fortiextender_controller`.

    Misc: `gui_email_collection`, `gui_object_colors`.

    Note that some of these are gated by the device: enabling a controller page
    on a model or licence that does not support it is silently ignored and will
    diff on every plan.
  EOT
  type = object({
    gui_advanced_policy           = optional(string)
    gui_allow_unnamed_policy      = optional(string)
    gui_implicit_policy           = optional(string)
    gui_local_in_policy           = optional(string)
    gui_multiple_interface_policy = optional(string)
    gui_policy_based_ipsec        = optional(string)
    gui_dynamic_routing           = optional(string)

    gui_antivirus              = optional(string)
    gui_application_control    = optional(string)
    gui_dnsfilter              = optional(string)
    gui_dos_policy             = optional(string)
    gui_file_filter            = optional(string)
    gui_ips                    = optional(string)
    gui_security_profile_group = optional(string)
    gui_voip_profile           = optional(string)
    gui_waf_profile            = optional(string)
    gui_webfilter              = optional(string)

    gui_dns_database     = optional(string)
    gui_dhcp_advanced    = optional(string)
    gui_load_balance     = optional(string)
    gui_multicast_policy = optional(string)
    gui_traffic_shaping  = optional(string)
    gui_explicit_proxy   = optional(string)

    gui_vpn    = optional(string)
    gui_sslvpn = optional(string)
    gui_ztna   = optional(string)

    gui_wireless_controller      = optional(string)
    gui_ap_profile               = optional(string)
    gui_fortiap_split_tunneling  = optional(string)
    gui_switch_controller        = optional(string)
    gui_fortiextender_controller = optional(string)

    gui_email_collection = optional(string)
    gui_object_colors    = optional(string)
  })
  default = {}
}

variable "ntp" {
  description = <<-EOT
    System NTP configuration. Fields:

    - `ntpsync` — synchronise the device clock from NTP. `enable` or `disable`.
    - `server_mode` — serve NTP to clients as well as consuming it. `enable` or
      `disable`.
    - `syncinterval` — minutes between synchronisation attempts.
    - `interfaces` — interface names to listen on when `server_mode` is
      `enable`; renders one `interface` block per entry.

    The upstream server list is deliberately not exposed: the resource ignores
    changes to both `ntpserver` and `interface`, so servers stay whatever the
    device has and listener interfaces are added out-of-band (see
    `fortios-ptn-fortigate-system-ntp-interface`). `interfaces` therefore only
    takes effect on initial creation.
  EOT
  type = object({
    ntpsync      = optional(string, "enable")
    server_mode  = optional(string, "enable")
    syncinterval = optional(number, 1)
    interfaces   = optional(list(string), [])
  })
  default = {}
}
