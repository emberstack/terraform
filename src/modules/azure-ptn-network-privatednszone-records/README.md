# Azure Private DNS Records (Pattern)

Map-driven record sets for an **existing** private DNS zone. The private-zone twin of
[`azure-ptn-network-dnszone-records`](../azure-ptn-network-dnszone-records/).

## Why this exists alongside the AVM module

[`Azure/avm-res-network-privatednszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-privatednszone/azurerm/latest)
bundles zone, records and vnet links into one module. That breaks down when the zone and its records are
owned by different configurations, or when records are added to a zone that already exists. This module
takes the zone as an ARM resource ID and creates nothing but records.

It pairs with [`azure-res-network-privatednszone`](../azure-res-network-privatednszone/) for the zone and
[`azure-ptn-network-privatednszone-vnet-links`](../azure-ptn-network-privatednszone-vnet-links/) for the
links.

## Usage

```hcl
module "records" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-privatednszone-records?ref=vX.Y.Z"

  private_dns_zone_resource_id = module.zone.resource_id

  private_dns_zone_records = {
    api = {
      name      = "api"
      type      = "A"
      a_records = ["10.0.1.10"]
    }

    legacy_alias = {
      name         = "legacy"
      type         = "CNAME"
      cname_record = "api.example.internal"
    }

    sip = {
      name = "_sip._tcp"
      type = "SRV"
      srv_records = [
        { priority = 10, weight = 60, port = 5060, target = "sip.example.internal" },
      ]
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

| `type` | Field | Shape |
|---|---|---|
| `A` | `a_records` | list of IPv4 addresses |
| `AAAA` | `aaaa_records` | list of IPv6 addresses |
| `CNAME` | `cname_record` | a single hostname |
| `MX` | `mx_records` | list of `{preference, exchange}` |
| `PTR` | `ptr_records` | list of hostnames |
| `SRV` | `srv_records` | list of `{priority, weight, port, target}` |
| `TXT` | `txt_records` | list of TXT string values |

## Notes

- **No NS or CAA records.** Azure private DNS does not support those record types, and this module
  rejects them at validation time rather than letting ARM fail the apply. That is the only interface
  difference from the public twin.
- **State address stability.** Each entry creates `azapi_resource.<lowercase type>["<key>"]`. Renaming a
  key, or changing an entry's `type`, moves the address and recreates the record set.
- **Record-set tags live in `properties.metadata`**, not resource `tags`. Per-record `tags` win over the
  module-level `tags` on a key collision.
- **Lower-case ARM property names.** The private-zone API spells the record-set body keys `ttl`,
  `aRecords`, `txtRecords`; the public-zone API uses `TTL`, `ARecords`, `TXTRecords`. The two modules look
  like each other but their bodies are deliberately cased differently, and ARM is case-sensitive here.
- **Two output shapes.** `private_dns_zone_records` is flat and keyed by your input key, with `type` on
  each entry; `private_dns_zone_records_by_type` groups by record type. The `type` field is upper-case
  while the grouping key is lower-case, so the two do not compose directly.
- **The zone is not created here.** `private_dns_zone_resource_id` must already exist; it is validated to
  be a `Microsoft.Network/privateDnsZones` ARM ID.
