variable "display_name" {
  description = "Display name of the application. 1–256 characters. Also used for the service principal, and in the default SAML certificate subject."
  type        = string

  validation {
    condition     = length(var.display_name) > 0 && length(var.display_name) <= 256
    error_message = "display_name must be between 1 and 256 characters."
  }
}

variable "description" {
  description = "Description of the application. Up to 1024 characters."
  type        = string
  default     = null

  validation {
    condition     = var.description == null || length(var.description) <= 1024
    error_message = "description must be 1024 characters or fewer."
  }
}

variable "sign_in_audience" {
  description = "Account types allowed to sign in. One of: AzureADMyOrg, AzureADMultipleOrgs, AzureADandPersonalMicrosoftAccount, PersonalMicrosoftAccount."
  type        = string
  default     = "AzureADMyOrg"
  nullable    = false

  validation {
    condition = contains(
      ["AzureADMyOrg", "AzureADMultipleOrgs", "AzureADandPersonalMicrosoftAccount", "PersonalMicrosoftAccount"],
      var.sign_in_audience
    )
    error_message = "sign_in_audience must be one of: AzureADMyOrg, AzureADMultipleOrgs, AzureADandPersonalMicrosoftAccount, PersonalMicrosoftAccount."
  }
}

variable "template_id" {
  description = <<-EOT
    ID of the Entra application gallery template to instantiate the
    application from. Leave null for a custom (non-gallery) application. Look
    an ID up by name with the `azuread_application_template` data source.

    Instantiating a template creates the service principal too, so the module
    adopts that one instead of creating another — `service_principal.enabled`
    must stay true.

    Changing it replaces the application, which means a new client ID.
  EOT

  type    = string
  default = null

  validation {
    condition     = var.template_id == null || can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.template_id))
    error_message = "template_id must be a UUID."
  }

  validation {
    condition     = var.template_id == null || var.service_principal.enabled
    error_message = "template_id requires service_principal.enabled — instantiating a template always creates a service principal, which the module adopts."
  }
}

variable "tags" {
  description = "Tags applied to the application. Free-form strings, not key/value pairs."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "owners" {
  description = <<-EOT
    Owners of the application.

    Map of `<stable-key> => <owner-id>` where `<owner-id>` is **either** a
    valid Entra object ID (UUID) **or** a user principal name (UPN). UPN
    values are resolved via Graph at plan time. Auto-detected by format.

    Examples:
      owners = {
        alice = "11111111-1111-1111-1111-111111111111"  # object_id
        bob   = "bob@example.com"                       # UPN — looked up via Graph
      }

    Set this explicitly. Left empty, the principal running the apply can end
    up as the application's owner — in CI, the pipeline identity.

    Owners of the service principal are separate — see
    `service_principal.owners`.

    Values must be known at plan time, object IDs included — the UUID-vs-UPN
    split cannot be made on a value that only exists after apply.

    UPN-based entries require the deploying principal to have at least
    `User.Read.All` Graph permission.
  EOT

  type     = map(string)
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.owners :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each value in owners must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }
}

variable "identifier_uris" {
  description = "Application ID URIs that uniquely identify the application within the tenant (or within a verified custom domain for a multi-tenant app). Needed when clients request tokens for the application's own API."
  type        = set(string)
  default     = []
  nullable    = false
}

variable "web" {
  description = <<-EOT
    Web platform configuration. Needed for browser sign-in flows (OpenID
    Connect, SAML reply URLs); leave null for daemon / client-credential
    applications.

    - `redirect_uris` — each must be an `http(s)` URL or a URN, and must match
      what the client sends byte for byte.
    - `homepage_url` — home page or landing page of the application.
    - `logout_url` — front-channel logout URL.
    - `implicit_grant` — let the authorize endpoint return an ID token and/or
      access token directly. Only for clients that use the implicit or hybrid
      flow; an authorization code flow does not need it.
  EOT

  type = object({
    redirect_uris = optional(set(string), [])
    homepage_url  = optional(string)
    logout_url    = optional(string)
    implicit_grant = optional(object({
      id_token_issuance_enabled     = optional(bool, false)
      access_token_issuance_enabled = optional(bool, false)
    }))
  })
  default = null

  validation {
    condition = var.web == null || alltrue([
      for uri in var.web.redirect_uris : can(regex("(?i)^(https?://|urn:)", uri))
    ])
    error_message = "Each web.redirect_uris entry must be an http(s) URL or a URN."
  }
}

variable "api" {
  description = <<-EOT
    Settings for the API the application exposes.

    - `mapped_claims_enabled` — lets the application receive claims customised
      by a claims mapping policy without a custom signing key. Without it, or
      without such a key, sign-in fails with AADSTS50146. Only allowed on a
      single-tenant (`AzureADMyOrg`) application: on a multi-tenant one it lets
      any tenant author a claims mapping policy for the app.
    - `requested_access_token_version` — `1` or `2`. Must be `2` when
      `sign_in_audience` includes personal Microsoft accounts.
  EOT

  type = object({
    mapped_claims_enabled          = optional(bool, false)
    requested_access_token_version = optional(number)
  })
  default = null

  validation {
    condition = (
      var.api == null ||
      var.api.requested_access_token_version == null ||
      contains([1, 2], var.api.requested_access_token_version)
    )
    error_message = "api.requested_access_token_version must be 1 or 2."
  }

  validation {
    condition = (
      var.api == null ||
      !var.api.mapped_claims_enabled ||
      var.sign_in_audience == "AzureADMyOrg"
    )
    error_message = "api.mapped_claims_enabled is only safe on a single-tenant (AzureADMyOrg) application: on a multi-tenant one it lets anyone author a claims mapping policy for the app. Use a custom signing key instead."
  }

  validation {
    condition = (
      !contains(["AzureADandPersonalMicrosoftAccount", "PersonalMicrosoftAccount"], var.sign_in_audience) ||
      (var.api != null && var.api.requested_access_token_version == 2)
    )
    error_message = "api.requested_access_token_version must be 2 when sign_in_audience includes personal Microsoft accounts."
  }
}

variable "api_permissions" {
  description = <<-EOT
    API permissions the application requests (`required_resource_access`).

    Each entry names a resource application by its client ID — Microsoft Graph
    is `00000003-0000-0000-c000-000000000000` — and the permissions requested
    from it: `type = "Scope"` for a delegated permission, `type = "Role"` for
    an application permission.

    Entra accepts at most 50 resource applications and 400 permissions in
    total.

    Declaring a permission does not grant it. Admin consent is a separate step
    this module does not perform.
  EOT

  type = list(object({
    resource_app_id = string
    resource_access = list(object({
      id   = string
      type = string
    }))
  }))
  default  = []
  nullable = false

  validation {
    condition = alltrue(flatten([
      for p in var.api_permissions : [
        for a in p.resource_access : contains(["Role", "Scope"], a.type)
      ]
    ]))
    error_message = "Each api_permissions[*].resource_access[*].type must be Role or Scope."
  }

  validation {
    condition = alltrue(flatten([
      for p in var.api_permissions : concat(
        [can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", p.resource_app_id))],
        [for a in p.resource_access : can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", a.id))]
      )
    ]))
    error_message = "Each api_permissions[*].resource_app_id and resource_access[*].id must be a UUID."
  }

  validation {
    condition = (
      length(var.api_permissions) <= 50 &&
      length(flatten([for p in var.api_permissions : p.resource_access])) <= 400
    )
    error_message = "api_permissions is limited to 50 resource applications and 400 permissions in total."
  }
}

variable "group_membership_claims" {
  description = "Group memberships Entra emits in the `groups` claim of issued tokens. Any of: None, SecurityGroup, DirectoryRole, ApplicationGroup, All. Empty leaves the claim out."
  type        = set(string)
  default     = []
  nullable    = false

  validation {
    condition = alltrue([
      for v in var.group_membership_claims :
      contains(["None", "SecurityGroup", "DirectoryRole", "ApplicationGroup", "All"], v)
    ])
    error_message = "Each group_membership_claims entry must be one of: None, SecurityGroup, DirectoryRole, ApplicationGroup, All."
  }
}

variable "optional_claims" {
  description = <<-EOT
    Optional claims to add to issued tokens, listed per token type:
    `access_token`, `id_token` and `saml2_token`. Each claim takes:

    - `name` — the optional claim, e.g. `groups`; with `source = "user"`, the
      name of the user-object extension property.
    - `source` — null for a predefined optional claim, `user` for an extension
      property.
    - `essential` — whether the client needs the claim for a smooth sign-in.
    - `additional_properties` — modifiers for the claim, e.g. `emit_as_roles`
      or `sam_account_name`.
  EOT

  type = object({
    access_token = optional(list(object({
      name                  = string
      source                = optional(string)
      essential             = optional(bool, false)
      additional_properties = optional(list(string), [])
    })), [])
    id_token = optional(list(object({
      name                  = string
      source                = optional(string)
      essential             = optional(bool, false)
      additional_properties = optional(list(string), [])
    })), [])
    saml2_token = optional(list(object({
      name                  = string
      source                = optional(string)
      essential             = optional(bool, false)
      additional_properties = optional(list(string), [])
    })), [])
  })
  default = null

  validation {
    condition = var.optional_claims == null || alltrue([
      for c in concat(var.optional_claims.access_token, var.optional_claims.id_token, var.optional_claims.saml2_token) :
      length(c.name) > 0 && (c.source == null || c.source == "user")
    ])
    error_message = "Each optional claim needs a name, and a source that is either null or \"user\"."
  }

  validation {
    condition = var.optional_claims == null || alltrue(flatten([
      for c in concat(var.optional_claims.access_token, var.optional_claims.id_token, var.optional_claims.saml2_token) : [
        for p in c.additional_properties : contains([
          "cloud_displayname", "dns_domain_and_sam_account_name", "emit_as_roles",
          "include_externally_authenticated_upn_without_hash", "include_externally_authenticated_upn",
          "max_size_limit", "netbios_domain_and_sam_account_name", "on_premise_security_identifier",
          "sam_account_name", "use_guid",
        ], p)
      ]
    ]))
    error_message = "Each optional claim additional_properties entry must be one of: cloud_displayname, dns_domain_and_sam_account_name, emit_as_roles, include_externally_authenticated_upn_without_hash, include_externally_authenticated_upn, max_size_limit, netbios_domain_and_sam_account_name, on_premise_security_identifier, sam_account_name, use_guid."
  }
}

variable "app_roles" {
  description = <<-EOT
    App roles the application defines, keyed by a stable name.

    - `id` — UUID, unique within the application. Generate it once and keep
      it: assignments reference the role by ID.
    - `display_name` / `description` — shown during assignment and consent.
    - `allowed_member_types` — `User` (users and groups), `Application`, or
      both.
    - `value` — what the `roles` claim carries; null for a role that only
      gates access.
    - `enabled` — defaults to true.

    To grant one of these roles through `user_assignments` and
    `group_assignments`, set `assignment_app_role_id` to its `id`.
  EOT

  type = map(object({
    id                   = string
    display_name         = string
    description          = string
    allowed_member_types = set(string)
    value                = optional(string)
    enabled              = optional(bool, true)
  }))
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for r in values(var.app_roles) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", r.id))
    ])
    error_message = "Each app_roles[*].id must be a UUID."
  }

  validation {
    condition     = length(distinct([for r in values(var.app_roles) : lower(r.id)])) == length(var.app_roles)
    error_message = "app_roles ids must be unique."
  }

  validation {
    condition = alltrue([
      for r in values(var.app_roles) :
      length(r.allowed_member_types) > 0 && alltrue([for t in r.allowed_member_types : contains(["User", "Application"], t)])
    ])
    error_message = "Each app_roles[*].allowed_member_types must be a non-empty set of User and/or Application."
  }
}

variable "password" {
  description = <<-EOT
    Client secret to generate for the application. Leave null for none.

    The secret value is returned by the `password` output and persisted in
    state. Prefer federated credentials or certificates where the client
    supports them.

    - `display_name` — label shown against the secret in Entra.
    - `end_date` — RFC 3339 expiry timestamp; the provider default applies
      when null.
  EOT

  type = object({
    display_name = optional(string, "default")
    end_date     = optional(string)
  })
  default = null

  validation {
    condition = (
      var.password == null ||
      var.password.end_date == null ||
      can(formatdate("YYYY-MM-DD", var.password.end_date))
    )
    error_message = "password.end_date must be an RFC3339 timestamp (e.g. 2027-01-01T00:00:00Z)."
  }
}

variable "claims_mapping_policy" {
  description = <<-EOT
    Claims mapping policy to create and assign to the application's service
    principal. Customises the claims Entra issues to this application — the
    way to emit a value the directory does not store, such as a transformed
    UPN.

    - `display_name` — display name of the policy object.
    - `definition` — the raw policy JSON. Build it with `jsonencode()` rather
      than hand-writing the escaping.

    Requires `service_principal.enabled`. An OIDC client of an application
    carrying one of these must fetch metadata with `?appid=<client_id>`
    appended, or the token signing keys will not validate. Unless the
    application has a custom signing key, also set `api.mapped_claims_enabled`.
  EOT

  type = object({
    display_name = string
    definition   = string
  })
  default = null

  validation {
    condition     = var.claims_mapping_policy == null || var.service_principal.enabled
    error_message = "claims_mapping_policy requires service_principal.enabled — the policy is assigned to the service principal, not to the application."
  }

  validation {
    condition     = var.claims_mapping_policy == null || can(jsondecode(var.claims_mapping_policy.definition))
    error_message = "claims_mapping_policy.definition must be valid JSON."
  }
}

variable "service_principal" {
  description = <<-EOT
    Service principal (enterprise application) for the application. Created
    by default; set `enabled = false` to manage the registration alone.

    - `app_role_assignment_required` — when true, only users and groups
      assigned through `user_assignments` / `group_assignments` can sign in.
    - `owners` — same UUID-or-UPN map as the top-level `owners`.
    - `tags` — free-form tags. Mutually exclusive with `feature_tags`.
    - `feature_tags` — Entra's well-known tags. An application has to carry
      `enterprise` to appear in the Enterprise Applications blade, where
      assignments are managed. `custom_single_sign_on` marks custom SAML SSO
      and means nothing to an OIDC application.
    - `saml` — puts the service principal into SAML mode and issues a
      token-signing certificate; together those produce the federation
      metadata a service provider consumes. Leave null for OIDC.
      - `login_url` — where the service provider starts sign-in ("Sign on
        URL" in the portal).
      - `relay_state` — relative URI the service provider redirects to after
        sign-in.
      - `notification_email_addresses` — who Entra notifies as the signing
        certificate nears expiry.
      - `certificate.display_name` — defaults to `CN=<display_name>`.
      - `certificate.end_date` — RFC 3339 expiry timestamp; the provider
        default applies when null.
  EOT

  type = object({
    enabled                      = optional(bool, true)
    app_role_assignment_required = optional(bool, false)
    owners                       = optional(map(string), {})
    tags                         = optional(set(string), [])

    feature_tags = optional(object({
      enterprise            = optional(bool, false)
      custom_single_sign_on = optional(bool, false)
      gallery               = optional(bool, false)
      hide                  = optional(bool, false)
    }))

    saml = optional(object({
      login_url                    = optional(string)
      relay_state                  = optional(string)
      notification_email_addresses = optional(set(string), [])

      certificate = optional(object({
        display_name = optional(string)
        end_date     = optional(string)
      }), {})
    }))
  })
  default  = {}
  nullable = false

  validation {
    condition     = var.service_principal.feature_tags == null || length(var.service_principal.tags) == 0
    error_message = "service_principal.tags and service_principal.feature_tags are mutually exclusive — the azuread provider rejects both."
  }

  validation {
    condition     = var.service_principal.enabled || var.service_principal.saml == null
    error_message = "service_principal.saml requires service_principal.enabled."
  }

  validation {
    condition = (
      var.service_principal.saml == null ||
      var.service_principal.saml.certificate.end_date == null ||
      can(formatdate("YYYY-MM-DD", var.service_principal.saml.certificate.end_date))
    )
    error_message = "service_principal.saml.certificate.end_date must be an RFC3339 timestamp (e.g. 2027-01-01T00:00:00Z)."
  }

  validation {
    condition = var.service_principal.saml == null || alltrue([
      for v in var.service_principal.saml.notification_email_addresses :
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each service_principal.saml.notification_email_addresses entry must be an email address."
  }

  validation {
    condition = alltrue([
      for k, v in var.service_principal.owners :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each value in service_principal.owners must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }
}

variable "assignment_app_role_id" {
  description = <<-EOT
    App role granted by every entry in `user_assignments` and
    `group_assignments`.

    Defaults to Default Access (`00000000-0000-0000-0000-000000000000`), the
    role Graph accepts when an application declares no app roles of its own.
    For an application that does, set it to the `id` of one of `app_roles`, or
    of a role its gallery template defines.

    Changing it re-creates every assignment.
  EOT

  type     = string
  default  = "00000000-0000-0000-0000-000000000000"
  nullable = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.assignment_app_role_id))
    error_message = "assignment_app_role_id must be a UUID."
  }
}

variable "group_assignments" {
  description = <<-EOT
    Groups granted access to the application, as `<stable-key> => <object-id>`.

    Assignment does **not** cascade to nested groups: only direct members of
    an assigned group get access.

    Unlike `user_assignments`, values may be object IDs only known after
    apply, such as a group created in the same configuration.

    Requires `service_principal.enabled`.
  EOT

  type     = map(string)
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.group_assignments :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v))
    ])
    error_message = "Each value in group_assignments must be a valid Entra object ID (UUID)."
  }

  validation {
    condition     = length(var.group_assignments) == 0 || var.service_principal.enabled
    error_message = "group_assignments requires service_principal.enabled — assignments are made to the service principal."
  }
}

variable "user_assignments" {
  description = <<-EOT
    Users granted access to the application.

    Map of `<stable-key> => <user-id>` where `<user-id>` is **either** a
    valid Entra object ID (UUID) **or** a user principal name (UPN). UPN
    values are resolved via Graph at plan time. Auto-detected by format.

    Values must be known at plan time, object IDs included — the UUID-vs-UPN
    split cannot be made on a value that only exists after apply.

    Requires `service_principal.enabled`.
  EOT

  type     = map(string)
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.user_assignments :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each value in user_assignments must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }

  validation {
    condition     = length(var.user_assignments) == 0 || var.service_principal.enabled
    error_message = "user_assignments requires service_principal.enabled — assignments are made to the service principal."
  }
}
