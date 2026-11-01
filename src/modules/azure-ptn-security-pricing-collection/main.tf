# =============================================================================
# DEFENDER FOR CLOUD PLANS (Microsoft.Security/pricings)
# =============================================================================
# Every Defender plan of one subscription, keyed by the plan's ARM name, plus the
# optional per-account diagnostic setting that ships Defender for Storage malware
# scan results to Log Analytics.
#
# The subscription is the one the provider is configured against: a pricing is
# a subscription singleton, so there is nothing else to point it at.
#
# Pricing writes are serialised. The resource provider answers a second write
# that arrives while another plan of the same subscription is updating with a
# 409, so every pricing takes the same azapi lock.
#
# Nothing here sets `response_export_values` or `ignore_null_property`: a change
# to either alone is a PUT, so adopting existing plans by `terraform import`
# would cost a write on each. Unset optional fields are left out of the body
# instead.
# =============================================================================

data "azapi_client_config" "current" {}

locals {
  subscription_resource_id = "/subscriptions/${data.azapi_client_config.current.subscription_id}"

  # ARM returns a plan's extensions in a fixed order of its own, and azapi
  # compares lists by position, so they are sent in the order the caller lists
  # them rather than sorted.
  pricing_extensions = {
    for plan, pricing in var.pricings : plan => [
      for extension in pricing.extensions : merge(
        {
          isEnabled = extension.enabled ? "True" : "False"
          name      = extension.name
        },
        [for properties in(extension.additional_properties == null ? [] : [extension.additional_properties]) : { additionalExtensionProperties = properties }]...
      )
    ]
  }

  # Defender for Storage writes scan results through a diagnostic setting on
  # each account's `defenderForStorageSettings/current` extension. There is no
  # subscription-level switch, so every account in the subscription is listed,
  # Terraform-managed or not; an account created later is picked up on the next
  # apply. FileStorage (Azure Files has no on-upload scanning) and legacy v1
  # accounts are skipped.
  malware_scan_results_accounts = {
    for account in try(data.azapi_resource_list.storage_accounts[0].output.accounts, []) :
    account.name => account.id if contains(["StorageV2", "BlobStorage", "BlockBlobStorage"], account.kind)
  }
}

# -----------------------------------------------------------------------------
# Plans
# -----------------------------------------------------------------------------

resource "azapi_resource" "this" {
  for_each = var.pricings

  name      = each.key
  parent_id = local.subscription_resource_id
  type      = "Microsoft.Security/pricings@2024-01-01"
  body = {
    properties = merge(
      { pricingTier = each.value.tier },
      [for key, value in {
        extensions = length(local.pricing_extensions[each.key]) > 0 ? local.pricing_extensions[each.key] : null
        subPlan    = each.value.sub_plan
      } : { (key) = value } if value != null]...
    )
  }
  locks = ["${local.subscription_resource_id}/providers/Microsoft.Security/pricings"]
}

# -----------------------------------------------------------------------------
# Malware scan results
# -----------------------------------------------------------------------------

data "azapi_resource_list" "storage_accounts" {
  count = var.malware_scan_results == null ? 0 : 1

  parent_id = local.subscription_resource_id
  type      = "Microsoft.Storage/storageAccounts@2025-01-01"
  response_export_values = {
    accounts = "value[].{id: id, name: name, kind: kind}"
  }
}

# `Microsoft.Insights/diagnosticSettings` has never shipped a stable API version;
# 2021-05-01-preview is the newest and what AVM uses. The extension has one log
# category, `ScanResults`, and no metrics; it writes only to its own table, so no
# destination type is sent.
resource "azapi_resource" "malware_scan_results" {
  for_each = local.malware_scan_results_accounts

  name      = var.malware_scan_results.name
  parent_id = "${each.value}/providers/Microsoft.Security/defenderForStorageSettings/current"
  type      = "Microsoft.Insights/diagnosticSettings@2021-05-01-preview"
  body = {
    properties = {
      logAnalyticsDestinationType = null
      logs = [{
        category        = "ScanResults"
        categoryGroup   = null
        enabled         = true
        retentionPolicy = { days = 0, enabled = false }
      }]
      metrics     = []
      workspaceId = var.malware_scan_results.workspace_resource_id
    }
  }

  depends_on = [azapi_resource.this]

  lifecycle {
    precondition {
      condition     = try(var.pricings["StorageAccounts"].tier, "Free") == "Standard"
      error_message = "malware_scan_results needs the StorageAccounts plan on the Standard tier: the extension it writes through exists only then."
    }
  }
}
