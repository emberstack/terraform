# Azure Firewall Policy Rule Collection Group

One rule collection group (`Microsoft.Network/firewallPolicies/ruleCollectionGroups`) on an existing
firewall policy — its DNAT, network and application rule collections. A submodule of
[`azure-res-network-firewallpolicy`](../../).

## Usage

```hcl
module "dnat_sftp" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-firewallpolicy/modules/rule-collection-group?ref=vX.Y.Z"

  firewall_policy_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/firewallPolicies/afwp-example"
  name                        = "dnat-sftp"
  priority                    = 500

  nat_rule_collections = {
    dnat-sftp = {
      priority = 100
      rules = [{
        name                = "sftp"
        protocols           = ["TCP"]
        source_addresses    = ["*"]
        destination_address = "203.0.113.10"
        destination_ports   = ["22"]
        translated_address  = "10.0.2.4"
        translated_port     = "22"
      }]
    }
  }

  application_rule_collections = {
    arc-updates = {
      priority = 200
      rules = [{
        name              = "updates"
        protocols         = [{ type = "Https", port = 443 }]
        source_addresses  = ["10.0.2.0/24"]
        destination_fqdns = ["*.example.com"]
      }]
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf).

## Notes

- **Collections are keyed by name; rules are a list.** Collection names must be unique across all
  three kinds, since they share one array in ARM. Rules keep the order given, and their names must
  be unique within a collection.
- **Writes to one policy are serialised.** Every group locks the policy, so groups in one
  configuration apply one at a time. Another configuration writing to the same policy at once is
  what `retry` is for — raise `timeouts` with it, since the timeout bounds retrying.
- **ARM's names differ from the inputs' in places.** `destination_fqdns` on an application rule is
  ARM's `targetFqdns`; on a network rule it is `destinationFqdns`. The NAT action is sent as `Dnat`,
  the casing ARM stores, although the REST specification spells it `DNAT`.
- **Updates are slow.** A group change propagates to every firewall using the policy; several
  minutes for a one-rule change is normal.

## Migrating from `azurerm_firewall_policy_rule_collection_group`

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_firewall_policy_rule_collection_group.<name>'
terraform import 'azapi_resource.this' '<policy-id>/ruleCollectionGroups/<group-name>?api-version=2025-07-01'
terraform plan
```

The first plan after the import renders the collections as reordered, because Terraform diffs the
imported list by position while azapi matches by name. Compare the collections and rules by name
before applying; the plan should only drop the empty lists, `""` descriptions and `false` flags ARM
fills in.
