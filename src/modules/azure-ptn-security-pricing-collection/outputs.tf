output "pricings" {
  description = "Map of plans keyed by the input map key — `resource_id`, `tier` and `sub_plan`."
  value = {
    for plan, pricing in azapi_resource.this : plan => {
      resource_id = pricing.id
      tier        = var.pricings[plan].tier
      sub_plan    = var.pricings[plan].sub_plan
    }
  }
}

output "malware_scan_results" {
  description = "Map of malware-scan-results diagnostic settings keyed by storage account name — `resource_id`."
  value = {
    for account, setting in azapi_resource.malware_scan_results : account => {
      resource_id = setting.id
    }
  }
}
