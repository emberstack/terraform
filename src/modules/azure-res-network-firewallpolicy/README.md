# Azure Firewall Policy

An Azure Firewall policy (`Microsoft.Network/firewallPolicies`) — tier, threat intelligence,
IDPS, DNS proxy, SNAT private ranges and an optional base policy — with a management lock and
policy-scope role assignments. Rules live in rule collection groups, added with
[`modules/rule-collection-group`](./modules/rule-collection-group/) — see [Submodules](#submodules).
The firewall that uses the policy is [`azure-res-network-azurefirewall`](../azure-res-network-azurefirewall/).

## Why this exists alongside the AVM module

[`Azure/avm-res-network-firewallpolicy/azurerm`](https://github.com/Azure/terraform-azurerm-avm-res-network-firewallpolicy)
is azurerm-based, and so is its `rule_collection_groups` submodule. azurerm renders a group's
collections and rules as ordered nested blocks, so inserting a collection anywhere but last plans as
every later collection changing one slot. This module is AzAPI throughout: ARM's collections and
rules carry names, azapi matches them by name, and an insertion plans as an insertion.

Input names follow the AVM module where they overlap, over a `resource_group_name` like the rest of
this family.

## Usage

```hcl
module "firewall_policy" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-firewallpolicy?ref=vX.Y.Z"

  name                                     = "afwp-example"
  resource_group_name                      = "rg-example"
  location                                 = "westeurope"
  firewall_policy_sku                      = "Premium"
  firewall_policy_threat_intelligence_mode = "Deny"

  firewall_policy_intrusion_detection = {
    mode = "Deny"
  }

  firewall_policy_dns = {
    proxy_enabled = true
    servers       = ["10.0.0.4"]
  }

  firewall_policy_private_ip_ranges = ["IANAPrivateRanges", "203.0.113.0/24"]
}

module "platform_rules" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-firewallpolicy/modules/rule-collection-group?ref=vX.Y.Z"

  firewall_policy_resource_id = module.firewall_policy.resource_id
  name                        = "platform"
  priority                    = 100

  network_rule_collections = {
    nrc-dns = {
      priority = 100
      rules = [{
        name                  = "dns"
        protocols             = ["UDP", "TCP"]
        source_addresses      = ["10.0.0.0/8"]
        destination_addresses = ["10.0.0.4"]
        destination_ports     = ["53"]
      }]
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Submodules

| Submodule | What it manages |
|---|---|
| [`modules/rule-collection-group`](./modules/rule-collection-group/) | One rule collection group — its NAT, network and application rule collections |

A policy's groups usually have different owners — platform rules, per-workload rules, DNAT for one
service — so each is a unit of its own rather than an input here.

## Notes

- **Not everything a policy can hold is modelled.** ARM writes are full replaces, and the body never
  carries explicit proxy, TLS inspection, insights, the threat intelligence allowlist, the SQL
  redirect or a managed identity. Do not manage a policy with any of them configured elsewhere —
  the next write sends a body without them.
- **No diagnostic settings.** `Microsoft.Network/firewallPolicies` does not support them; the
  firewall emits the logs.
- **`firewall_policy_private_ip_ranges` replaces Azure's default.** Include `IANAPrivateRanges`
  alongside any public ranges that must not be source-NATed.
- **IDPS needs Premium,** and the tier must match the firewalls using the policy.
- **A `ReadOnly` lock blocks the rule collection groups.** Use `CanNotDelete` if groups are managed
  separately.

## Migrating from `azurerm_firewall_policy`

Resource *types* differ, so `moved` blocks do not apply. Adopt the existing policy instead:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_firewall_policy.<name>'
terraform import 'azapi_resource.this' '<policy-id>?api-version=2025-07-01'
terraform plan
```

Expect the family's usual post-import settle — see
[Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi) — and check that it only
sheds properties ARM re-derives before applying.
