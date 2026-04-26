resource "fortios_dnsfilter_profile" "this" {
  name              = var.name
  comment           = var.comment
  log_all_domain    = var.log_all_domain
  block_botnet      = var.block_botnet
  block_action      = var.block_action
  safe_search       = var.safe_search
  youtube_restrict  = var.youtube_restrict
  strip_ech         = var.strip_ech
  sdns_ftgd_err_log = var.sdns_ftgd_err_log
  sdns_domain_log   = var.sdns_domain_log

  dynamic "domain_filter" {
    for_each = var.domain_filter_table != null && var.domain_filter_table > 0 ? [1] : []
    content {
      domain_filter_table = var.domain_filter_table
    }
  }

  dynamic "external_ip_blocklist" {
    for_each = var.external_ip_blocklists
    content {
      name = external_ip_blocklist.value
    }
  }

  dynamic "ftgd_dns" {
    for_each = length(var.ftgd_dns_filters) > 0 ? [1] : []
    content {
      options = var.ftgd_dns_options

      dynamic "filters" {
        for_each = var.ftgd_dns_filters
        content {
          id       = filters.value.id
          category = filters.value.category
          action   = filters.value.action
          log      = filters.value.log
        }
      }
    }
  }
}
