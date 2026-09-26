# Azure Route Server BGP Connection

One BGP peering (`Microsoft.Network/virtualHubs/bgpConnections`) between an existing route server
and an NVA. A submodule of [`azure-res-network-routeserver`](../../), kept separate because the
peering usually belongs to the configuration that deploys the NVA, not the one that owns the route
server.

## Usage

```hcl
module "nva_peering" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-network-routeserver/modules/bgp-connection?ref=vX.Y.Z"

  route_server_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualHubs/rs-example"
  name                     = "nva-example"
  peer_asn                 = 65001
  peer_ip                  = "10.0.1.4"
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf).

## Notes

- **The connection only lets the route server accept the session.** The NVA still has to peer with
  both of the route server's `virtual_router_ips`, as remote AS `virtual_router_asn` — both are
  outputs of the parent module.
- **`peer_asn` must not be a reserved ASN.** Validation rejects the Azure and IANA reservations
  listed in the Route Server FAQ, which include 65515, the route server's own ASN.
- **A `ReadOnly` lock on the route server blocks this module.** Use `CanNotDelete` there if
  peerings are managed separately.

## Migrating from `azurerm_route_server_bgp_connection`

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_route_server_bgp_connection.<name>'
terraform import 'azapi_resource.this' '<route-server-id>/bgpConnections/<connection-name>?api-version=2025-07-01'
terraform plan   # expect a settle that only sheds read-only properties; never a destroy
```
