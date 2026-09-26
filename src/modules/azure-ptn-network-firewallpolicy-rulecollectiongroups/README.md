# Azure Firewall Policy Rule Collection Groups (Pattern)

Many rule collection groups (`Microsoft.Network/firewallPolicies/ruleCollectionGroups`) on an
existing firewall policy, from one map — each group's DNAT, network and application rule
collections. For one group managed as its own unit, use
[`azure-res-network-firewallpolicy/modules/rule-collection-group`](../azure-res-network-firewallpolicy/modules/rule-collection-group/),
which takes the same shape per group.

## Usage

```hcl
module "platform_rules" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-firewallpolicy-rulecollectiongroups?ref=vX.Y.Z"

  firewall_policy_resource_id = module.firewall_policy.resource_id

  groups = {
    platform = {
      name     = "rcg-platform"
      priority = 100
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
    deny = {
      name     = "rcg-deny"
      priority = 65000
      network_rule_collections = {
        nrc-deny-all = {
          priority = 65000
          action   = "Deny"
          rules = [{
            name                  = "deny-all"
            protocols             = ["Any"]
            source_addresses      = ["*"]
            destination_addresses = ["*"]
            destination_ports     = ["*"]
          }]
        }
      }
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf).

## Notes

- **Keys are state addresses.** Each group is `azapi_resource.this["<key>"]`; its ARM name is `name`,
  defaulting to the key. Renaming a key re-addresses the group, and a changed `name` replaces it.
- **Omitting a group deletes it.** An entry left out of the map — or an empty map — removes that
  group from the policy, which makes a conditional entry a clean on/off switch.
- **Writes are serialised on the policy.** Groups apply one at a time within a run, and each
  group's default deadline is 30 minutes for every group in the map, since its wait in the queue
  counts against it. Another configuration writing to the same policy at once is what `retry` is
  for.
- **Everything in the submodule's notes applies per group** — collection names unique across the
  three kinds, rules kept in order, ARM's `targetFqdns` and `Dnat` spellings.

## Migrating from `azurerm_firewall_policy_rule_collection_group`

One import per group, at the key the group has in `groups`:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_firewall_policy_rule_collection_group.<name>["<key>"]'
terraform import 'azapi_resource.this["<key>"]' '<policy-id>/ruleCollectionGroups/<group-name>?api-version=2025-07-01'
terraform plan
```

The first plan after the imports renders collections as reordered, because Terraform diffs each
imported list by position while azapi matches by name. Compare collections and rules by name before
applying; the plan should only drop the empty lists, `""` descriptions and `false` flags ARM fills
in.
