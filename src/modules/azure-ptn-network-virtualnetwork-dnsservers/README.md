# Pattern: Virtual Network DNS Servers

Sets the DNS servers on an existing virtual network without redeclaring the vnet itself. Classified `ptn` rather than `res` because it does not create or manage a primary Azure resource — it only writes `properties.dhcpOptions.dnsServers` on the parent vnet.

## Why this pattern exists

DNS servers on an Azure virtual network are typically set inline as part of the vnet body. That works fine — until the DNS servers come from a resource that lives **inside** the same vnet (most commonly an NVA firewall in a hub-spoke topology with a Forced Tunnel pattern):

```
hub-vnet  ──[needs DNS server IP]──>  hub-firewall
hub-firewall  ──[needs subnet]──>  hub-vnet     ← cycle
```

Splitting DNS-server assignment into a downstream Terraform module breaks the cycle:

```
hub-vnet  →  hub-firewall  →  this pattern (sets DNS on hub-vnet)
```

`azapi_update_resource` is purpose-built for exactly this: it does not create a new Azure resource — it writes a subset of an existing one's properties. ARM offers no property-level PATCH for virtual networks (only tags), so the write is a read-merge-write of the whole vnet; everything not named in `body` is echoed back untouched, subnets and peerings included. This module formalises the pattern.

## Usage

### Hub vnet pointing DNS at a firewall NVA inside the same vnet

```hcl
module "hub_vnet_dns_servers" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-virtualnetwork-dnsservers?ref=vX.Y.Z"

  virtual_network_resource_id = module.hub_vnet.resource_id
  dns_servers                 = [module.hub_firewall.private_ip_address]
}
```

### Spoke vnet pointing DNS at the hub firewall

```hcl
module "spoke_vnet_dns_servers" {
  source = "..."

  virtual_network_resource_id = module.spoke_vnet.resource_id
  dns_servers                 = [data.terraform_remote_state.hub.outputs.firewall_private_ip]
}
```

### Reverting to Azure-provided DNS

Pass an empty list:

```hcl
module "vnet_dns_servers" {
  source = "..."

  virtual_network_resource_id = module.vnet.resource_id
  dns_servers                 = []
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Requirements

- The deploying principal must have `Microsoft.Network/virtualNetworks/write` on the target vnet (typically `Network Contributor`).

## Notes

- **No new Azure resource is created.** The Azure REST view is a write of `dhcpOptions` on the existing vnet body. Destroying this module does not destroy the vnet.
- **Destroying this module leaves the DNS servers in place.** `azapi_update_resource` performs no operation on delete, so the last-written values persist with nothing managing them. To revert to Azure-provided DNS, set `dns_servers = []` and apply *before* removing the module.
- **The vnet's owner must not clear `dhcpOptions`.** Whatever module owns the vnet writes its body on every apply, so it can revert this one. Whether it does depends on the owner:
  - **`azurerm_virtual_network`** — `dns_servers` is `Optional + Computed`, so an owner that simply leaves it unset preserves whatever is live. Nothing to do. Setting it is the conflict case below.
  - **AzAPI, including AVM** — check whether the owner sends the property as null when it has no DNS input of its own. `Azure/avm-res-network-virtualnetwork` does: at v0.20.0 it builds `dhcpOptions = var.dns_servers != null ? {...} : null` and sets no `ignore_null_property`, so the null reaches ARM. Guard it with `lifecycle { ignore_changes = [body.properties.dhcpOptions] }` on the owner's vnet resource — refresh pulls the live value into state and `ignore_changes` keeps it, so the owner's write carries the DNS servers back. You cannot add a `lifecycle` block to a module you do not control, so in practice this means an override file merged into the owner's module directory.

  An owner that omits the key entirely is safe without a guard: ARM treats an absent property as "no change". Confirm which of the two you have before relying on it.
- **Apply ordering matters.** This module assumes the target vnet already exists. In a hub-spoke topology, place this leaf downstream of both the vnet and whatever produces the DNS server IP (typically a firewall).
- **Conflicts with inline DNS in the vnet body.** If you also set `dns_servers` on the AVM `avm-res-network-virtualnetwork` module's input, both will fight over the same ARM property on every apply. Use one or the other; the inline form is fine for spoke-to-static-DNS, this module is for breaking cycles.
