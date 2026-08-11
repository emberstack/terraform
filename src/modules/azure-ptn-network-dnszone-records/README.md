# Azure Public DNS Records (Pattern)

Map-driven record sets for an **existing** public DNS zone. One map of records in, nine record-set
resource types out, keyed back into one output map.

## Why this exists alongside the AVM module

[`Azure/avm-res-network-dnszone/azurerm`](https://registry.terraform.io/modules/Azure/avm-res-network-dnszone/azurerm/latest)
creates a zone and its records together. That is fine when one configuration owns both, and awkward when
they are owned separately — a platform team owning zones while workload teams add records, or records
being added to a zone that already exists. This module takes the zone as an ARM resource ID and creates
nothing but records.

It pairs with [`azure-res-network-dnszone`](../azure-res-network-dnszone/), which creates the zone
itself.

## Usage

### A, CNAME and TXT records

```hcl
module "records" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-ptn-network-dnszone-records?ref=vX.Y.Z"

  dns_zone_resource_id = module.zone.resource_id

  dns_zone_records = {
    apex = {
      name      = "@"
      type      = "A"
      a_records = ["203.0.113.10"]
    }

    www = {
      name         = "www"
      type         = "CNAME"
      cname_record = "example.com"
    }

    spf = {
      name        = "@"
      type        = "TXT"
      ttl         = 300
      txt_records = ["v=spf1 include:example.com -all"]
    }
  }
}
```

### Records that carry structure

```hcl
module "records" {
  source = "..."

  dns_zone_resource_id = module.zone.resource_id
  tags                 = { managed_by = "platform" }

  dns_zone_records = {
    mail = {
      name = "@"
      type = "MX"
      mx_records = [
        { preference = 10, exchange = "mail1.example.com" },
        { preference = 20, exchange = "mail2.example.com" },
      ]
    }

    sip = {
      name = "_sip._tcp"
      type = "SRV"
      srv_records = [
        { priority = 10, weight = 60, port = 5060, target = "sip.example.com" },
      ]
    }

    ca_allowlist = {
      name = "@"
      type = "CAA"
      caa_records = [
        { flags = 0, tag = "issue", value = "example.com" },
      ]
    }
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

`type` selects which resource is created and which type-specific field must be populated:

| `type` | Field | Shape |
|---|---|---|
| `A` | `a_records` | list of IPv4 addresses |
| `AAAA` | `aaaa_records` | list of IPv6 addresses |
| `CNAME` | `cname_record` | a single hostname |
| `MX` | `mx_records` | list of `{preference, exchange}` |
| `NS` | `ns_records` | list of nameserver hostnames |
| `PTR` | `ptr_records` | list of hostnames |
| `SRV` | `srv_records` | list of `{priority, weight, port, target}` |
| `TXT` | `txt_records` | list of TXT string values |
| `CAA` | `caa_records` | list of `{flags, tag, value}` |

Both rules are enforced by validation: an unknown `type` is rejected, and so is an entry whose
type-specific field is missing or empty.

## Notes

- **State address stability.** Each entry creates `azapi_resource.<lowercase type>["<key>"]` — so an `A`
  record keyed `apex` is `azapi_resource.a["apex"]`. Renaming a key, or changing an entry's `type`, moves
  the address and recreates the record set. Pick stable keys.
- **Record-set tags live in `properties.metadata`**, not resource `tags`. ARM models a DNS record set's
  tags as metadata; the module maps `tags` there for you. Per-record `tags` win over the module-level
  `tags` on a key collision.
- **`cname_record` is a single value, not a list.** ARM allows exactly one CNAME target per record set.
  Its default is `null`, which is the "this entry is not a CNAME" sentinel the validation checks — an
  empty string would pass that check and send an empty `cname` to ARM.
- **`ttl` defaults to 3600.** Set it per entry where a shorter one matters, as in the `spf` example above.
- **The public-zone API cases its body keys inconsistently, and ARM is case-sensitive about it.** Eight
  are PascalCase (`TTL`, `ARecords`, `AAAARecords`, `CNAMERecord`, `MXRecords`, `NSRecords`,
  `PTRRecords`, `SRVRecords`, `TXTRecords`) and one is not: `caaRecords`. The private-zone twin is
  lowerCamel throughout (`ttl`, `aRecords`, …). Don't "tidy" either module's casing to match the other.
- **Two output shapes.** `dns_zone_records` is flat and keyed by your input key, with `type` on each
  entry. `dns_zone_records_by_type` groups by record type. Note the type field is upper-case (`"A"`) while
  the grouping key is lower-case (`a`), so the two do not compose directly.
- **The zone is not created here.** `dns_zone_resource_id` must already exist; it is validated to be a
  `Microsoft.Network/dnsZones` ARM ID.
