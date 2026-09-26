# Azure Virtual Network Gateway

A VPN or ExpressRoute gateway (`Microsoft.Network/virtualNetworkGateways`) in an existing
`GatewaySubnet`, on public IP addresses owned elsewhere, with diagnostic settings, a
management lock and gateway-scope role assignments.

## Why this exists alongside the AVM modules

The AzAPI AVM repository for this resource,
[`Azure/terraform-azapi-avm-res-network-virtualnetworkgateway`](https://github.com/Azure/terraform-azapi-avm-res-network-virtualnetworkgateway),
still holds the unimplemented module template. Its predecessor,
[`Azure/avm-ptn-vnetgateway/azurerm`](https://github.com/Azure/terraform-azurerm-avm-ptn-vnetgateway),
is archived, runs on azurerm, and is a pattern that also builds the subnet, public IPs, route
table, local network gateways and connections.

This module is the gateway alone. Its input names follow the archived pattern where the two
overlap — `sku`, `type`, the `vpn_*` settings, `ip_configurations` and its `apipa_addresses` —
and it takes a `resource_group_name`, matching the rest of this family.

## Usage

An active-active, zone-redundant VPN gateway with BGP, one instance of which peers with an
on-premises device over an APIPA address:

```hcl
module "gateway" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-virtualnetworkgateway?ref=vX.Y.Z"

  name                = "vgw-example"
  resource_group_name = "rg-example"
  location            = "westeurope"
  sku                 = "VpnGw2AZ"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/GatewaySubnet"

  vpn_active_active_enabled = true
  vpn_bgp_enabled           = true
  vpn_bgp_settings = {
    asn = 65010
  }

  ip_configurations = {
    primary = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-01"
      apipa_addresses               = ["169.254.21.2"]
    }
    secondary = {
      public_ip_address_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/publicIPAddresses/pip-example-02"
    }
  }

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
    }
  }

  lock = {
    kind = "CanNotDelete"
  }

  tags = {
    environment = "production"
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Requirements

- The deploying principal needs `Microsoft.Network/virtualNetworkGateways/write` in the
  resource group, `Microsoft.Network/virtualNetworks/subnets/join/action` on `GatewaySubnet`
  and `Microsoft.Network/publicIPAddresses/join/action` on each public IP — all carried by
  `Network Contributor`.
- Role assignments additionally need `Role Based Access Control Administrator` at the gateway.
  See [Role assignments](../../../docs/role-assignments.md).

## Notes

- **Only site-to-site and BGP are modelled.** ARM writes are full replaces, and the body never
  carries point-to-site (`vpnClientConfiguration`), NAT rules, policy groups, custom routes, a
  default site or DNS forwarding. Do not manage a gateway that has any of them configured
  elsewhere with this module — the next write sends a body without them.
- **Active-active means exactly two IP configurations.** `ip_configurations` must hold two
  entries when `vpn_active_active_enabled` is true and one when it is false, and validation
  enforces the pairing at plan time.
- **Map keys are ARM names.** Each key names an IP configuration and the BGP peering address
  that references it. Pick them once.
- **BGP peering addresses are matched by position.** ARM returns one per IP configuration, and
  the entries have no `name` for azapi to match on, so the sent and returned lists are paired
  element by element. Both lists are built from `ip_configurations` in the same key order, which
  keeps them aligned.
- **`vpn_bgp_settings = null` sends no BGP settings at all.** ARM keeps its defaults (ASN 65515,
  weight 0), and there is nowhere to put `apipa_addresses` — validation rejects them in that
  case instead of dropping them silently.
- **ASN 65515 is accepted; the other reserved ASNs are not.** 65515 is the ASN Azure assigns a
  gateway by default. The rest of the Azure and IANA reservations in the VPN Gateway FAQ are
  rejected.
- **Private IP allocation is always `Dynamic`.** It is the only value the service accepts for a
  gateway IP configuration, so it is not an input.
- **Public IPs are not created here.** Pass existing Standard, static public IP addresses.
- **Timeouts are long on purpose.** Creates often take 45 minutes or more. The defaults match
  the azurerm provider's for this resource; AzAPI's own 30 minutes would abandon a create
  mid-flight.

## Migrating from `azurerm_virtual_network_gateway`

| azurerm | this module |
|---|---|
| `type` | `type` |
| `vpn_type` | `vpn_type` |
| `sku` | `sku` |
| `generation` | `vpn_generation` |
| `active_active` | `vpn_active_active_enabled` |
| `bgp_enabled` (`enable_bgp` in older 4.x configurations) | `vpn_bgp_enabled` |
| `private_ip_address_enabled` | `vpn_private_ip_address_enabled` |
| `ip_sec_replay_protection_enabled` | `vpn_ip_sec_replay_protection_enabled` |
| `bgp_route_translation_for_nat_enabled` | `vpn_bgp_route_translation_for_nat_enabled` |
| `remote_vnet_traffic_enabled` | `express_route_remote_vnet_traffic_enabled` |
| `virtual_wan_traffic_enabled` | `express_route_virtual_wan_traffic_enabled` |
| `ip_configuration { name, public_ip_address_id, subnet_id }` | `ip_configurations["<name>"].public_ip_address_resource_id`, plus one `subnet_resource_id` |
| `bgp_settings { asn, peer_weight }` | `vpn_bgp_settings` |
| `bgp_settings.peering_addresses[*].apipa_addresses` | `ip_configurations[*].apipa_addresses` |

Resource *types* differ, so `moved` blocks do not apply. Adopt the existing gateway instead:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_virtual_network_gateway.<name>'
terraform import 'azapi_resource.this' '<gateway-resource-id>?api-version=2025-07-01'
terraform plan
```

The `?api-version=` suffix keeps the import on the module's pinned version. Expect the
family's usual post-import settle — see
[Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi) — and check that it
only sheds properties ARM re-derives before applying. A plan that shows a destroy means the
import did not land; do not apply it.

Existing gateway-scope role assignments are adopted the same way, by importing their GUIDs —
see [Adopting an assignment that already exists](../../../docs/role-assignments.md#adopting-an-assignment-that-already-exists).
