# Azure Firewall

A policy-managed Azure Firewall (`Microsoft.Network/azureFirewalls`, `AZFW_VNet`) in an existing
`AzureFirewallSubnet`, with its data-plane public IPs passed in, an optional management IP
configuration and the management public IP it needs, diagnostic settings, a management lock and
firewall-scope role assignments. Rules live in the policy —
[`azure-res-network-firewallpolicy`](../azure-res-network-firewallpolicy/).

## Why this exists alongside the AVM module

[`Azure/avm-res-network-azurefirewall/azurerm`](https://github.com/Azure/terraform-azurerm-avm-res-network-azurefirewall)
is azurerm-based. This module is AzAPI throughout, creates the management public IP that only the
firewall uses, and takes a `resource_group_name` like the rest of this family. Input names follow
the AVM module where they overlap.

## Usage

```hcl
module "firewall" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-azurefirewall?ref=vX.Y.Z"

  name                = "afw-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/AzureFirewallSubnet"
  firewall_sku_tier   = "Premium"
  firewall_policy_id  = module.firewall_policy.resource_id

  ip_configurations = {
    primary = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
      primary                       = true
    }
    ingress-01 = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-02"
    }
  }

  firewall_management_ip_configuration = {
    subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/AzureFirewallManagementSubnet"
  }

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
    }
  }
}
```

`private_ip_address` is the next hop for user-defined routes, and the DNS server address when the
policy's DNS proxy is on.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Notes

- **Zones are fixed at creation, and ARM reorders them.** ARM returns `["2", "3", "1"]` for a
  request of `["1", "2", "3"]`, and azapi compares a list of strings position by position. The
  firewall and its management public IP therefore take `body.zones` from state once they exist —
  a write resends ARM's own ordering of the same set — which also means a later change to
  `firewall_zones` or the management IP's `zones` is ignored rather than attempted.
- **Only the policy-managed, virtual-network form is modelled.** Classic, firewall-embedded rule
  collections and the Virtual WAN form (`AZFW_Hub`) are not.
- **The primary IP configuration holds the subnet and the private IP,** and is always sent first.
  The others only add public IPs.
- **Diagnostic settings must name every category.** ARM materialises all sixteen log categories
  whatever is sent, so `log_categories` lists each with its enabled flag — see the variable's
  description for the names.
- **Timeouts are long on purpose.** The defaults match the azurerm provider's for this resource.

## Migrating from `azurerm_firewall`

Resource *types* differ, so `moved` blocks do not apply. Adopt the firewall, its management public
IP and each diagnostic setting instead:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_firewall.<name>' 'azurerm_public_ip.<management>' 'azurerm_monitor_diagnostic_setting.<name>'
terraform import 'azapi_resource.this'                              '<firewall-id>?api-version=2025-07-01'
terraform import 'azapi_resource.management_public_ip[0]'           '<management-public-ip-id>?api-version=2025-07-01'
terraform import 'azapi_resource.diagnostic_settings["<key>"]'      '<firewall-id>/providers/Microsoft.Insights/diagnosticSettings/<name>?api-version=2021-05-01-preview'
terraform plan
```

Expect the family's usual post-import settle — see
[Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi). The diagnostic setting
plans as a reorder of its categories, because ARM's stored order differs from the module's
alphabetical one; check the enabled flags match before applying.
