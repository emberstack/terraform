# Entra ID Service Principal

A service principal (`azuread_service_principal`) for an application registered somewhere
else: a Microsoft first-party application, or another tenant's multi-tenant application.

## Why this exists alongside `entra-res-application`

`entra-res-application` always creates the application registration, and its service
principal is the one for *that* application. Some services instead need the tenant's copy of
an application that lives in Microsoft's tenant, which no configuration here can register. Entra
Domain Services is the usual example: on any deployment path other than the portal, its
*Domain Controller Services* service principal has to exist before the managed domain can be
created, and nothing in ARM or Bicep creates it.

## Usage

The *Domain Controller Services* service principal Entra Domain Services needs, adopting it if
the portal or an earlier `New-MgServicePrincipal` already created it:

```hcl
module "domain_controller_services" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-serviceprincipal?ref=vX.Y.Z"

  client_id    = "2565bd9d-da50-47d4-8b85-4c97f669dc36"
  use_existing = true
  notes        = "Required by Entra Domain Services."
}
```

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Requirements

- Creating or adopting a service principal needs `Application.ReadWrite.All`, or a directory
  role that carries it, such as Application Administrator or Cloud Application Administrator.
- Owners given as UPNs are resolved through Graph, which additionally needs `User.Read.All`.

## Notes

- **`prevent_destroy` is hardcoded.** `terraform destroy` fails on any configuration using this
  module, and so does a change to `client_id`. A service that depends on a service principal
  reaches it through this object, and a replacement comes back with a new object ID and none of
  its app role assignments or consents. To retire one, `terraform state rm` it and delete it
  deliberately. See
  [`prevent_destroy` on service principals](../../../docs/modules/entra.md#prevent_destroy-on-service-principals).
- **`use_existing` adopts without an import, and adoption is not exclusive.** Two
  configurations can both adopt the same object and then fight over it. Manage each service
  principal from one place.
- **Owners, description and notes are managed.** Unset means empty: the first apply against an
  adopted service principal removes owners, a description or notes that were set elsewhere.
- **Tags are not, unless you set them.** `tags = null` leaves the service principal's tags as
  they are, which for a first-party application are Microsoft's. A set replaces all of them.
