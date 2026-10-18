# Azure Entra Domain Services

A Microsoft Entra Domain Services managed domain (`Microsoft.AAD/domainServices`), with
additional replica sets, secure LDAP, diagnostic settings, a management lock and
managed-domain-scope role assignments.

## Why this exists alongside the AVM modules

There is no Terraform AVM module for this resource. `avm-res-aad-domainservice` is listed as
*proposed* in the AVM index, and its repository,
[`Azure/terraform-azurerm-avm-res-aad-domainservice`](https://github.com/Azure/terraform-azurerm-avm-res-aad-domainservice),
still holds the unimplemented module template. The Bicep module,
[`avm/res/aad/domain-service`](https://github.com/Azure/bicep-registry-modules/tree/main/avm/res/aad/domain-service),
is published.

This module follows the Bicep module's coverage, with three deliberate differences:

- The initial replica set is `location` plus `subnet_resource_id`, not the first entry of a
  list. A managed domain cannot exist without it, and cannot move it once created.
- Security and notification settings are grouped into `security` and `notifications` objects
  named the way the azurerm provider names them, so a configuration ported off
  `azurerm_active_directory_domain_service` keeps its field names.
- `filtered_sync_enabled` defaults to `false`, as the azurerm provider does. The Bicep module
  defaults it on, which limits synchronisation to a scope that has to be set separately, in
  Entra ID.

## Usage

An Enterprise managed domain with a second replica set and internal-only secure LDAP:

```hcl
module "domain_services" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/azure-res-aad-domainservice?ref=vX.Y.Z"

  domain_name         = "aaddscontoso.com"
  resource_group_name = "rg-example"
  location            = "westeurope"
  sku                 = "Enterprise"
  subnet_resource_id  = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example/subnets/snet-domain-services"

  replica_sets = [
    {
      location           = "northeurope"
      subnet_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.Network/virtualNetworks/vnet-example-neu/subnets/snet-domain-services"
    },
  ]

  notifications = {
    additional_recipients = ["ops@example.com"]
  }

  secure_ldap = {
    external_access_enabled = false
  }
  secure_ldap_certificate = {
    pfx_certificate          = var.ldaps_pfx_base64
    pfx_certificate_password = var.ldaps_pfx_password
  }

  diagnostic_settings = {
    workspace = {
      workspace_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-example/providers/Microsoft.OperationalInsights/workspaces/law-example"
    }
  }

  lock = {
    kind = "CanNotDelete"
  }
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Requirements

Entra Domain Services has tenant-level prerequisites that the portal creates for you and an
ARM deployment does not. Microsoft's
[PowerShell guide](https://learn.microsoft.com/entra/identity/domain-services/powershell-create-instance)
lists them:

- **The `Domain Controller Services` service principal**, application ID
  `2565bd9d-da50-47d4-8b85-4c97f669dc36` in global Azure
  (`6ba9a5d4-8456-4118-b521-9c5ca10cdf84` in other clouds), must exist in the tenant.
- **The `AAD DC Administrators` group.** Its members administer the managed domain.
- **The `Microsoft.AAD` resource provider** registered on the subscription.
- **A network security group on the subnet.** The PowerShell guide creates one allowing TCP
  3389 from `CorpNetSaw` and TCP 5986 from `AzureActiveDirectoryDomainServices`, and
  associates it before creating the domain. This module creates no network resources.
- **Permissions.** Microsoft documents Global Administrator in Entra ID and Contributor on the
  subscription to enable the service. Changing security settings later needs Application
  Administrator and Groups Administrator in Entra ID, plus the Domain Services Contributor
  Azure role.
- Role assignments additionally need `Role Based Access Control Administrator` at the managed
  domain. See [Role assignments](../../../docs/role-assignments.md).

A tenant can hold one managed domain.

## Notes

- **The create finishes before the domain is usable.** ARM reports success while the domain
  controllers are still provisioning — Microsoft documents up to an hour more. The azurerm
  provider polls until every replica set reports two controllers; AzAPI cannot wait on response
  content, so `domain_controller_ip_addresses` can be empty after the first apply and fills in
  on a later refresh. Guard anything that writes DNS servers on its length.
- **Replacing the resource deletes the domain.** Changing `name`, `location` or
  `resource_group_name` plans a replacement, and deleting a managed domain deletes its OUs,
  group policy, computer accounts and password hashes. Use `lock`.
- **Some fields cannot change, and are not replace triggers.** `domain_name`, the initial
  replica set's subnet and `domain_configuration_type` are fixed at create. azurerm forces a
  replacement on them; this module sends the change as an update for ARM to reject, because a
  failed apply is better than a planned deletion.
- **Every security setting is sent on every write.** The REST defaults enable NTLMv1, TLS 1.0
  and RC4, and an ARM write resets what it leaves out. TLS 1.0/1.1 is always sent disabled —
  the service no longer offers it.
- **The secure LDAP certificate is sent on every write and stored in state**, as the azurerm
  provider does. AzAPI's `sensitive_body` would keep it out of state, but it omits an
  unchanged path from the request, and whether ARM keeps the installed certificate across a
  write that enables LDAPS without one is untested. Treat state as secret. The service does not
  renew the certificate; alert on `secure_ldap.certificate_not_after`.
- **`secure_ldap = null` turns LDAPS off.** It is sent explicitly, so LDAPS enabled in the
  portal is disabled by the next apply.
- **Replica sets are compared by position.** Their entries carry no name. Append to
  `replica_sets` and remove from its end; inserting diffs every entry after the insertion.
- **Replica set regions are sent as display names.** ARM returns a replica set's region as its
  display name (`West Europe`) whatever was sent, and azapi compares it literally, so the module
  looks each region up in the subscription's region catalogue (`GET /subscriptions/{id}/locations`,
  on every plan) and sends the display name. Either spelling works as input; a region missing
  from the catalogue fails the plan. The resource's own `location` keeps the input spelling.
- **Forest trusts are not modelled.** `resourceForestSettings` is never sent, so do not manage a
  domain with trusts here.
- **The filtered sync scope lives in Entra ID**, not on this resource. Set it before turning
  `filtered_sync_enabled` on.
- **Cloud-only users must change their password** after the managed domain is created before
  they can sign in to it. Entra ID only generates the NTLM and Kerberos hashes Domain Services
  needs from that point on, and hashes from an earlier, deleted managed domain cannot be
  reused.
- **Timeouts are long on purpose.** The defaults match the azurerm provider's for this
  resource; AzAPI's own 30 minutes is too short for deletes and replica set changes.

## Migrating from `azurerm_active_directory_domain_service`

| azurerm | this module |
|---|---|
| `name`, `domain_name`, `location`, `resource_group_name`, `sku` | same names |
| `initial_replica_set { subnet_id }` | `subnet_resource_id` |
| `azurerm_active_directory_domain_service_replica_set` resources | `replica_sets` |
| `domain_configuration_type` | `domain_configuration_type` |
| `filtered_sync_enabled` | `filtered_sync_enabled` |
| `security { ... }` | `security` — same field names; `tls_v1_enabled` is gone |
| `notifications { ... }` | `notifications` — same field names |
| `secure_ldap { enabled, external_access_enabled }` | `secure_ldap` (null = disabled) |
| `secure_ldap { pfx_certificate, pfx_certificate_password }` | `secure_ldap_certificate` |

Check the defaults before porting. azurerm defaults every `security` field to `false`, which
includes `sync_ntlm_passwords`, `sync_kerberos_passwords` and `sync_on_prem_passwords`; this
module defaults those three to `true` and `kerberos_armoring_enabled` to `true`. State the
values you run today explicitly, or the first apply changes them.

Resource *types* differ, so `moved` blocks do not apply. Adopt the existing domain instead. The
azurerm resource ID carries an `/initialReplicaSetId/<guid>` suffix that is not part of the ARM
ID — drop it:

```bash
terraform state pull > backup.tfstate
terraform state rm 'azurerm_active_directory_domain_service.<name>'
terraform import 'azapi_resource.this' '<domain-service-resource-id>?api-version=2025-06-01'
terraform plan
```

The `?api-version=` suffix keeps the import on the module's pinned version. Expect the
family's usual post-import settle — see
[Migrating to AzAPI](../../../docs/modules/azure.md#migrating-to-azapi) — and read the first
plan for security settings it would change before applying. A plan that shows a destroy means
the import did not land.
