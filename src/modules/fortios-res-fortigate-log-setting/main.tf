# =============================================================================
# FORTIGATE LOG SETTINGS (fortios_log_setting)
# =============================================================================
# `log setting` is a per-VDOM singleton: create and update both write it, and
# destroy sends `null` for every managed attribute, which FortiOS resets to
# its default. Every input defaults to `null`, which the provider does not
# send, so an input left unset stays unmanaged and keeps what the device has.
# =============================================================================

resource "fortios_log_setting" "this" {
  fwpolicy_implicit_log  = var.fwpolicy_implicit_log
  fwpolicy6_implicit_log = var.fwpolicy6_implicit_log
  expolicy_implicit_log  = var.expolicy_implicit_log

  local_in_allow          = var.local_in_allow
  local_in_deny_unicast   = var.local_in_deny_unicast
  local_in_deny_broadcast = var.local_in_deny_broadcast
  local_in_policy_log     = var.local_in_policy_log
  local_out               = var.local_out
  local_out_ioc_detection = var.local_out_ioc_detection

  resolve_ip         = var.resolve_ip
  resolve_port       = var.resolve_port
  extended_log       = var.extended_log
  extended_utm_log   = var.extended_utm_log
  log_policy_comment = var.log_policy_comment
  log_policy_name    = var.log_policy_name
  detailed_svc_name  = var.detailed_svc_name
  zone_name          = var.zone_name

  brief_traffic_format = var.brief_traffic_format
  log_user_in_upper    = var.log_user_in_upper
  user_anonymize       = var.user_anonymize
  anonymization_hash   = var.anonymization_hash

  log_invalid_packet     = var.log_invalid_packet
  daemon_log             = var.daemon_log
  neighbor_event         = var.neighbor_event
  long_live_session_stat = var.long_live_session_stat
  web_svc_perf           = var.web_svc_perf
  fortiview_weekly_data  = var.fortiview_weekly_data

  rest_api_set         = var.rest_api_set
  rest_api_get         = var.rest_api_get
  rest_api_performance = var.rest_api_performance

  faz_override                       = var.faz_override
  syslog_override                    = var.syslog_override
  tacacs_accounting_server_alternate = var.tacacs_accounting_server_alternate
}
