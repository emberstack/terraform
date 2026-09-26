# Azure Route Server

An Azure Route Server — in ARM, a `Microsoft.Network/virtualHubs` resource with no virtual WAN —
with its IP configuration in `RouteServerSubnet`, the public IP it needs, diagnostic settings, a
management lock and route-server-scope role assignments. BGP peers are added with
[`modules/bgp-connection`](./modules/bgp-connection/) — see [Submodules](#submodules).

## Why this exists alongside the AVM module

[`Azure/avm-ptn-network-routeserver/azurerm`](https://github.com/Azure/terraform-azurerm-avm-ptn-network-routeserver)
mixes providers — the hub and IP configuration on AzAPI, the public IP, BGP connections, lock and
role assignments on azurerm — and waits a fixed five minutes on every create before reading the
router's addresses back. It also takes its BGP connections as a map on the route server itself,
so the configuration that owns an NVA cannot add its own peering without owning the route server.

This module is AzAPI throughout, keeps the route server and its peerings in separate units, and
takes a `resource_group_name` like the rest of this family. Input names follow the AVM module
where they overlap.

## Usage

```hcl
module "route_server" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-routeserver?ref=vX.Y.Z"

  name                    = "rs-example"
  resource_group_name     = "rg-example"
  location                = "westeurope"
  subnet_resource_id      = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/RouteServerSubnet"
  enable_branch_to_branch = true

  lock = {
    kind = "CanNotDelete"
  }

  tags = {
    environment = "production"
  }
}

# Typically in the configuration that deploys the NVA
module "nva_peering" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-routeserver/modules/bgp-connection?ref=vX.Y.Z"

  route_server_resource_id = module.route_server.resource_id
  name                     = "nva-example"
  peer_asn                 = 65001
  peer_ip                  = "10.0.1.4"
}
```

The NVA then peers with both addresses in `virtual_router_ips`, as remote AS `virtual_router_asn`.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Submodules

| Submodule | What it manages |
|---|---|
| [`modules/bgp-connection`](./modules/bgp-connection/) | One BGP peering between the route server and an NVA |

The route server and its peerings usually have different owners — the hub network owns the route
server, the configuration that deploys an NVA knows its address and ASN — so a peering is a unit of
its own rather than an input here.

## Requirements

- The deploying principal needs `Microsoft.Network/virtualHubs/write`,
  `Microsoft.Network/publicIPAddresses/write` in the resource group,
  `Microsoft.Network/virtualNetworks/subnets/join/action` on `RouteServerSubnet` and
  `Microsoft.Network/publicIPAddresses/join/action` on the public IP — all carried by
  `Network Contributor`.
- Role assignments additionally need `Role Based Access Control Administrator` at the route server.
  See [Role assignments](../../../docs/role-assignments.md).

## Notes

- **The public IP is created here, and its zones are fixed at creation.** The default is
  zone-redundant. Adopting a non-zonal address needs `routeserver_public_ip_config.zones = []` —
  any other value replaces the address the route server is using.
- **`virtual_router_ips` is empty after the create.** Azure assigns the router's addresses when the
  IP configuration provisions, which is after the hub itself is created, so the apply that builds
  the route server records none. The next refresh fills them in; a peer configuration that reads
  them should run after that.
- **Deploying a route server disrupts traffic.** Azure updates the virtual network's control plane
  on deploy, and VMs lose connectivity to on-premises for a while. Deploy into production in a
  maintenance window.
- **A `ReadOnly` lock blocks peerings.** It covers the route server's children, so
  `modules/bgp-connection` cannot write while one is in place. `CanNotDelete` does not.
- **Timeouts are long on purpose.** A deployment can take up to 30 minutes, which is AzAPI's
  own default. The defaults here match the azurerm provider's for this resource.

## Migrating from `azurerm_route_server`

| azurerm | this module |
|---|---|
| `name`, `resource_group_name`, `location`, `tags` | same |
| `subnet_id` | `subnet_resource_id` |
| `branch_to_branch_traffic_enabled` | `enable_branch_to_branch` |
| `hub_routing_preference` | `hub_routing_preference` |
| `public_ip_address_id` (an `azurerm_public_ip` managed alongside) | the module's own public IP — `routeserver_public_ip_config` |

Resource *types* differ, so `moved` blocks do not apply. Adopt the existing resources instead —
the route server, its IP configuration (azurerm names it `ipConfig1`, this module's default) and the
public IP:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_route_server.<name>' 'azurerm_public_ip.<name>'
terraform import 'azapi_resource.this'             '<route-server-id>?api-version=2025-07-01'
terraform import 'azapi_resource.ip_configuration' '<route-server-id>/ipConfigurations/ipConfig1?api-version=2025-07-01'
terraform import 'azapi_resource.public_ip'        '<public-ip-id>?api-version=2025-07-01'
terraform plan
```

The `?api-version=` suffix keeps each import on the module's pinned version. Expect the family's
usual post-import settle — see [Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi)
— and check that it only sheds properties ARM re-derives before applying. A plan that shows a
destroy or a replacement means an import did not land, or the public IP's zones differ; do not
apply it.

`azurerm_route_server_bgp_connection` moves to `modules/bgp-connection` the same way — see its
README.
