# Entra ID Application

Creates an Entra ID application registration and, by default, its service principal (enterprise application). Optionally adds a client secret, a claims mapping policy, SAML single sign-on with a token-signing certificate, and user and group assignments.

Owners and user assignments take either Entra object IDs or user principal names, the same convention as [`entra-res-group`](../entra-res-group/). Group assignments take object IDs only.

## Usage

### OpenID Connect web sign-in

```hcl
module "portal_sso" {
  source = "git::https://github.com/emberstack/terraform.git//src/modules/entra-res-application?ref=vX.Y.Z"

  display_name = "portal-sso"
  description  = "Portal sign-in"
  owners       = { eve = "eve@example.com" }

  web = {
    redirect_uris = ["https://portal.example.com/signin-oidc"]
  }

  api_permissions = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
      resource_access = [
        { id = "37f7f235-527c-4136-accd-4a02d197296e", type = "Scope" }, # openid
        { id = "14dad69e-099b-42c9-810b-d002981feec1", type = "Scope" }, # profile
        { id = "64a6cdd6-aab1-4aaf-94b8-3cc8405e90d0", type = "Scope" }, # email
      ]
    },
  ]

  # Confidential client: the server exchanges the code for tokens.
  password = {}

  service_principal = {
    app_role_assignment_required = true
    owners                       = { eve = "eve@example.com" }
    feature_tags                 = { enterprise = true }
  }

  group_assignments = {
    portal_users = "00000000-0000-0000-0000-000000000001"
  }
  user_assignments = {
    alice = "alice@example.com"
  }
}
```

### Daemon with application permissions

No `web` block and no assignments — the application signs in as itself.

```hcl
module "automation" {
  source = "..."

  display_name = "automation"
  owners       = { eve = "..." }

  api_permissions = [
    {
      resource_app_id = "00000003-0000-0000-c000-000000000000" # Microsoft Graph
      resource_access = [
        { id = "df021288-bdef-4463-88db-98f22de89214", type = "Role" }, # User.Read.All
      ]
    },
  ]

  service_principal = {
    tags = ["automation"]
  }
}
```

Admin consent for the declared permissions is not granted by this module.

### SAML single sign-on

```hcl
module "vendor_sso" {
  source = "..."

  display_name    = "vendor-sso"
  owners          = { eve = "..." }
  identifier_uris = ["https://vendor.example.com/saml/metadata"]

  web = {
    redirect_uris = ["https://vendor.example.com/saml/acs"]
  }

  service_principal = {
    app_role_assignment_required = true
    feature_tags = {
      enterprise            = true
      custom_single_sign_on = true
    }

    saml = {
      login_url                    = "https://vendor.example.com/saml/login"
      notification_email_addresses = ["ops@example.com"]
    }
  }

  group_assignments = {
    vendor_users = "00000000-0000-0000-0000-000000000002"
  }
}

# Hand these to the service provider.
# module.vendor_sso.saml.metadata_url
# module.vendor_sso.saml.entity_id
```

### Customised claims

A claims mapping policy emits a value the directory does not store. On a single-tenant application, `api.mapped_claims_enabled` lets the app accept the customised claims without a custom signing key.

```hcl
module "reporting_sso" {
  source = "..."

  display_name = "reporting-sso"
  owners       = { eve = "..." }

  web = {
    redirect_uris = ["https://reporting.example.com/signin-oidc"]
  }

  api = {
    mapped_claims_enabled = true
  }

  claims_mapping_policy = {
    display_name = "reporting-sso-claims"
    definition = jsonencode({
      ClaimsMappingPolicy = {
        Version              = 1
        IncludeBasicClaimSet = "true"
        ClaimsSchema = [
          { Source = "user", ID = "employeeid", JwtClaimType = "employee_id" },
        ]
      }
    })
  }
}
```

The client must then fetch OIDC metadata with `?appid=<client_id>` appended, or the token signing keys will not validate.

## Inputs and outputs

See [`variables.tf`](variables.tf) and [`outputs.tf`](outputs.tf). Every variable and output
carries a description, and CI enforces that.

## Related modules

- [`entra-res-group`](../entra-res-group/) — groups to assign to the application.

## Requirements

The provider must be authenticated as a principal that can create applications and service principals — typically **Application Administrator** or **Cloud Application Administrator** for user authentication, or `Application.ReadWrite.All` for app-only authentication. A claims mapping policy additionally needs `Policy.ReadWrite.ApplicationConfiguration` (app-only) or **Application Administrator** (user). UPN-based owners and user assignments need `User.Read.All`.

## Notes

- **Assignment does not cascade to nested groups.** Only direct members of an assigned group get access.
- **Every assignment uses the Default Access role** (`00000000-0000-0000-0000-000000000000`), the implicit role of an application that defines no app roles of its own.
- **`service_principal.tags` and `service_principal.feature_tags` are mutually exclusive** — the provider rejects both. An application needs `feature_tags.enterprise` to appear in the Enterprise Applications blade, where assignments are managed.
- **`api.mapped_claims_enabled` is rejected on a multi-tenant application**, where it would let any tenant author a claims mapping policy for the app.
- **The client secret is persisted in state** and returned by the sensitive `password` output. Prefer federated credentials or certificates where the client supports them.
- Removing one entry from `user_assignments` or `group_assignments` only destroys that single assignment.
