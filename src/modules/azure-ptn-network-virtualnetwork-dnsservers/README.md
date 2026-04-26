# Pattern: Virtual Network DNS Servers

Sets the DNS servers on an existing virtual network without redeclaring the vnet itself. Classified `ptn` rather than `res` because it does not create or manage a primary Azure resource — `azurerm_virtual_network_dns_servers` just PATCHes `properties.dhcpOptions.dnsServers` on the parent vnet.

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

The `azurerm_virtual_network_dns_servers` Terraform resource type is purpose-built for exactly this: it does not create a new Azure resource — it just PATCHes the existing vnet's `dhcpOptions.dnsServers`. This module formalises the pattern.

## Usage

### Hub vnet pointing DNS at a firewall NVA inside the same vnet

```hcl
module "hub_vnet_dns_servers" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-virtualnetwork-dnsservers?ref=v0.1.0"

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

## Inputs

| Name | Type | Description |
|---|---|---|
| `virtual_network_resource_id` | `string` | **Required.** ARM resource ID of the existing virtual network. |
| `dns_servers` | `list(string)` | **Required.** List of DNS server IP addresses. Empty list reverts to Azure-provided DNS. |

## Outputs

| Name | Description |
|---|---|
| `resource_id` | Resource ID of the DNS-servers assignment (equals the parent vnet's ID). |
| `dns_servers` | The DNS servers assigned to the virtual network. |
| `virtual_network_resource_id` | Resource ID of the virtual network whose DNS servers are managed. |

## Requirements

- Terraform `>= 1.15`
- `hashicorp/azurerm` `>= 4.81, < 5.0`
- The deploying principal must have `Microsoft.Network/virtualNetworks/write` on the target vnet (typically `Network Contributor`).

## Notes

- **No new Azure resource is created.** The Azure REST view is just a PATCH on the existing vnet body. Destroying this module does not destroy the vnet — it sets `dhcpOptions.dnsServers` to null (Azure-provided DNS).
- **Apply ordering matters.** This module assumes the target vnet already exists. In a hub-spoke topology, place this leaf downstream of both the vnet and whatever produces the DNS server IP (typically a firewall).
- **Conflicts with inline DNS in the vnet body.** If you also set `dns_servers` on the AVM `avm-res-network-virtualnetwork` module's input, both will fight over the same ARM property on every apply. Use one or the other; the inline form is fine for spoke-to-static-DNS, this module is for breaking cycles.
