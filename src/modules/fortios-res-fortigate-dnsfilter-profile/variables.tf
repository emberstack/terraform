variable "name" {
  description = "Name of the DNS filter profile. Becomes the FortiOS mkey and the value firewall policies reference as `dnsfilter_profile`."
  type        = string
}

variable "comment" {
  description = "Free-text comment stored on the profile."
  type        = string
  default     = ""
}

variable "log_all_domain" {
  description = "Log every DNS domain looked up through this profile, not just the ones that match a filter. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "block_botnet" {
  description = "Block DNS requests for known botnet command-and-control domains. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "block_action" {
  description = "How a blocked DNS request is answered. One of `block` (return the FortiGuard block IP), `redirect` (redirect to the block portal) or `block-sevrfail` (return SERVFAIL)."
  type        = string
  default     = "block"
}

variable "safe_search" {
  description = "Enforce safe search on supported search engines by rewriting their DNS answers. One of `enable` or `disable`. Required for `youtube_restrict` to have any effect."
  type        = string
  default     = "disable"
}

variable "youtube_restrict" {
  description = "YouTube restricted-access level: `strict`, `moderate` or `none`. Only applies when `safe_search` is `enable`. Left `null` by default so the field is not sent and FortiOS keeps its own default."
  type        = string
  default     = null
}

variable "strip_ech" {
  description = "Strip the Encrypted Client Hello (ECH) parameter from DNS HTTPS resource records, so downstream inspection can still see the SNI. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "sdns_ftgd_err_log" {
  description = "Log errors returned by the FortiGuard DNS rating service. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "sdns_domain_log" {
  description = "Log domains resolved via the FortiGuard secure DNS service. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "domain_filter_table" {
  description = "Numeric ID of an existing `dnsfilter.domain-filter` list to attach to this profile — typically the `id` output of the `fortios-res-fortigate-dnsfilter-domain-filter` module. `0` or `null` attaches no list: the `domain_filter` block is only emitted when the value is greater than zero."
  type        = number
  default     = 0
}

variable "external_ip_blocklists" {
  description = "Names of existing external IP blocklist (threat feed) objects to apply to DNS answers. One `external_ip_blocklist` block is emitted per name; an empty list emits none."
  type        = list(string)
  default     = []
}

variable "ftgd_dns_options" {
  description = "FortiGuard DNS filtering behaviour flags, e.g. `error-allow` to allow queries when the FortiGuard rating service is unreachable, or `ftgd-disable` to turn FortiGuard DNS rating off. Only takes effect when `ftgd_dns_filters` is non-empty, since it lives inside the gated `ftgd_dns` block."
  type        = string
  default     = "error-allow"
}

variable "ftgd_dns_filters" {
  description = <<-EOT
    FortiGuard DNS category filters. A non-empty list is what gates the whole
    `ftgd_dns` block — leaving it empty means no FortiGuard category filtering
    is configured and `ftgd_dns_options` is not sent either. Each entry:

    - `id`       — numeric filter entry ID, unique within the profile.
    - `category` — FortiGuard DNS category number to match.
    - `action`   — what to do on match: `block`, `monitor` or `ftgd-block`.
    - `log`      — log matches: `enable` or `disable`.
  EOT
  type = list(object({
    id       = number
    category = number
    action   = optional(string, "block")
    log      = optional(string, "enable")
  }))
  default = []
}
