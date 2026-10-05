# -----------------------------------------------------------------------------
# Implicit policy logging
# -----------------------------------------------------------------------------

variable "fwpolicy_implicit_log" {
  description = "Log traffic hitting the implicit (deny-all) IPv4 firewall policy. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.fwpolicy_implicit_log == null || contains(["enable", "disable"], var.fwpolicy_implicit_log)
    error_message = "fwpolicy_implicit_log must be enable or disable."
  }
}

variable "fwpolicy6_implicit_log" {
  description = "Log traffic hitting the implicit (deny-all) IPv6 firewall policy. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.fwpolicy6_implicit_log == null || contains(["enable", "disable"], var.fwpolicy6_implicit_log)
    error_message = "fwpolicy6_implicit_log must be enable or disable."
  }
}

variable "expolicy_implicit_log" {
  description = "Log traffic hitting the implicit explicit-proxy firewall policy. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.expolicy_implicit_log == null || contains(["enable", "disable"], var.expolicy_implicit_log)
    error_message = "expolicy_implicit_log must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Local-in and local-out traffic
# -----------------------------------------------------------------------------

variable "local_in_allow" {
  description = "Log allowed traffic addressed to the FortiGate itself. Has no effect while `local_in_policy_log` is `enable`, which logs per local-in policy instead. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.local_in_allow == null || contains(["enable", "disable"], var.local_in_allow)
    error_message = "local_in_allow must be enable or disable."
  }
}

variable "local_in_deny_unicast" {
  description = "Log denied unicast traffic addressed to the FortiGate itself. Has no effect while `local_in_policy_log` is `enable`. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.local_in_deny_unicast == null || contains(["enable", "disable"], var.local_in_deny_unicast)
    error_message = "local_in_deny_unicast must be enable or disable."
  }
}

variable "local_in_deny_broadcast" {
  description = "Log denied broadcast traffic addressed to the FortiGate itself. Has no effect while `local_in_policy_log` is `enable`. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.local_in_deny_broadcast == null || contains(["enable", "disable"], var.local_in_deny_broadcast)
    error_message = "local_in_deny_broadcast must be enable or disable."
  }
}

variable "local_in_policy_log" {
  description = "Log local-in traffic per local-in policy, as each policy's own log setting says, instead of through the three global `local_in_*` toggles. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.local_in_policy_log == null || contains(["enable", "disable"], var.local_in_policy_log)
    error_message = "local_in_policy_log must be enable or disable."
  }
}

variable "local_out" {
  description = "Log traffic the FortiGate originates itself. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.local_out == null || contains(["enable", "disable"], var.local_out)
    error_message = "local_out must be enable or disable."
  }
}

variable "local_out_ioc_detection" {
  description = "Run indicator-of-compromise detection on local-out traffic. Requires `local_out = \"enable\"`. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.local_out_ioc_detection == null || contains(["enable", "disable"], var.local_out_ioc_detection)
    error_message = "local_out_ioc_detection must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Traffic log content
# -----------------------------------------------------------------------------

variable "resolve_ip" {
  description = "Add resolved domain names to traffic logs where possible. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.resolve_ip == null || contains(["enable", "disable"], var.resolve_ip)
    error_message = "resolve_ip must be enable or disable."
  }
}

variable "resolve_port" {
  description = "Add resolved service names to traffic logs. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.resolve_port == null || contains(["enable", "disable"], var.resolve_port)
    error_message = "resolve_port must be enable or disable."
  }
}

variable "extended_log" {
  description = "Extended traffic logging. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.extended_log == null || contains(["enable", "disable"], var.extended_log)
    error_message = "extended_log must be enable or disable."
  }
}

variable "extended_utm_log" {
  description = "Extended UTM logging. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.extended_utm_log == null || contains(["enable", "disable"], var.extended_utm_log)
    error_message = "extended_utm_log must be enable or disable."
  }
}

variable "log_policy_comment" {
  description = "Insert the matching policy's comment into traffic logs. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.log_policy_comment == null || contains(["enable", "disable"], var.log_policy_comment)
    error_message = "log_policy_comment must be enable or disable."
  }
}

variable "log_policy_name" {
  description = "Insert the matching policy's name into traffic logs. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.log_policy_name == null || contains(["enable", "disable"], var.log_policy_name)
    error_message = "log_policy_name must be enable or disable."
  }
}

variable "detailed_svc_name" {
  description = "Log the specific service name rather than the top-most service group name. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.detailed_svc_name == null || contains(["enable", "disable"], var.detailed_svc_name)
    error_message = "detailed_svc_name must be enable or disable."
  }
}

variable "zone_name" {
  description = "Log zone names. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.zone_name == null || contains(["enable", "disable"], var.zone_name)
    error_message = "zone_name must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Format and user names
# -----------------------------------------------------------------------------

variable "brief_traffic_format" {
  description = "Brief-format traffic logging. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.brief_traffic_format == null || contains(["enable", "disable"], var.brief_traffic_format)
    error_message = "brief_traffic_format must be enable or disable."
  }
}

variable "log_user_in_upper" {
  description = "Log user names in upper case. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.log_user_in_upper == null || contains(["enable", "disable"], var.log_user_in_upper)
    error_message = "log_user_in_upper must be enable or disable."
  }
}

variable "user_anonymize" {
  description = "Anonymize user names in log messages. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.user_anonymize == null || contains(["enable", "disable"], var.user_anonymize)
    error_message = "user_anonymize must be enable or disable."
  }
}

variable "anonymization_hash" {
  description = "Salt for the hash used when `user_anonymize` is `enable`. `null` leaves it unmanaged."
  type        = string
  default     = null
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Event and statistics logging
# -----------------------------------------------------------------------------

variable "log_invalid_packet" {
  description = "Log invalid packets. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.log_invalid_packet == null || contains(["enable", "disable"], var.log_invalid_packet)
    error_message = "log_invalid_packet must be enable or disable."
  }
}

variable "daemon_log" {
  description = "Daemon logging. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.daemon_log == null || contains(["enable", "disable"], var.daemon_log)
    error_message = "daemon_log must be enable or disable."
  }
}

variable "neighbor_event" {
  description = "Neighbor event logging. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.neighbor_event == null || contains(["enable", "disable"], var.neighbor_event)
    error_message = "neighbor_event must be enable or disable."
  }
}

variable "long_live_session_stat" {
  description = "Statistics logging for long-lived sessions. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.long_live_session_stat == null || contains(["enable", "disable"], var.long_live_session_stat)
    error_message = "long_live_session_stat must be enable or disable."
  }
}

variable "web_svc_perf" {
  description = "Web service performance logging. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.web_svc_perf == null || contains(["enable", "disable"], var.web_svc_perf)
    error_message = "web_svc_perf must be enable or disable."
  }
}

variable "fortiview_weekly_data" {
  description = "Keep FortiView weekly data. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.fortiview_weekly_data == null || contains(["enable", "disable"], var.fortiview_weekly_data)
    error_message = "fortiview_weekly_data must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# REST API audit
# -----------------------------------------------------------------------------

variable "rest_api_set" {
  description = "Log REST API POST, PUT and DELETE requests — every write made through the `fortios` provider. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.rest_api_set == null || contains(["enable", "disable"], var.rest_api_set)
    error_message = "rest_api_set must be enable or disable."
  }
}

variable "rest_api_get" {
  description = "Log REST API GET requests. Every `plan` refresh reads over GET, so this logs heavily. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.rest_api_get == null || contains(["enable", "disable"], var.rest_api_get)
    error_message = "rest_api_get must be enable or disable."
  }
}

variable "rest_api_performance" {
  description = "Add memory and performance statistics to the REST API request logs. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.rest_api_performance == null || contains(["enable", "disable"], var.rest_api_performance)
    error_message = "rest_api_performance must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Log server overrides
# -----------------------------------------------------------------------------

variable "faz_override" {
  description = "Let this VDOM override the global FortiAnalyzer settings. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.faz_override == null || contains(["enable", "disable"], var.faz_override)
    error_message = "faz_override must be enable or disable."
  }
}

variable "syslog_override" {
  description = "Let this VDOM override the global syslog settings. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.syslog_override == null || contains(["enable", "disable"], var.syslog_override)
    error_message = "syslog_override must be enable or disable."
  }
}

variable "tacacs_accounting_server_alternate" {
  description = "Alternate between TACACS+ accounting servers. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.tacacs_accounting_server_alternate == null || contains(["enable", "disable"], var.tacacs_accounting_server_alternate)
    error_message = "tacacs_accounting_server_alternate must be enable or disable."
  }
}
