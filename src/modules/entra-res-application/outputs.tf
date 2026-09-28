output "application" {
  description = <<-EOT
    The application registration: `id` (the provider's resource ID,
    `/applications/<object_id>`), `object_id`, `client_id` and `display_name`,
    plus the URLs registered on it — `identifier_uris` and `redirect_uris` as
    sorted lists, and the web `logout_url`. A SAML service provider's own
    configuration needs the same URLs; reading them here keeps the two sides
    from drifting apart.
  EOT

  value = {
    id              = azuread_application.this.id
    object_id       = azuread_application.this.object_id
    client_id       = azuread_application.this.client_id
    display_name    = azuread_application.this.display_name
    identifier_uris = sort(azuread_application.this.identifier_uris)
    redirect_uris   = sort(try(one(azuread_application.this.web).redirect_uris, []))
    logout_url      = try(one(azuread_application.this.web).logout_url, null)
  }
}

output "service_principal" {
  description = "The service principal's `id` and `object_id`, or null when `service_principal.enabled` is false."
  value = var.service_principal.enabled ? {
    id        = azuread_service_principal.this[0].id
    object_id = azuread_service_principal.this[0].object_id
  } : null
}

output "claims_mapping_policy" {
  description = "The claims mapping policy's `id`, or null when `claims_mapping_policy` is unset."
  value = var.claims_mapping_policy != null ? {
    id = azuread_claims_mapping_policy.this[0].id
  } : null
}

output "saml" {
  description = <<-EOT
    What a SAML service provider needs to trust this application, or null when
    `service_principal.saml` is unset:

    - `metadata_url` — the application's federation metadata XML.
    - `login_url` / `logout_url` — the tenant's SAML endpoints.
    - `entity_id` — the identity provider's entity ID (issuer).
    - `certificate` — the signing certificate's `thumbprint` and `end_date`.
      The certificate itself is in `saml_certificate_value`.
  EOT

  value = var.service_principal.saml != null ? {
    metadata_url = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/federationmetadata/2007-06/federationmetadata.xml?appid=${azuread_application.this.client_id}"
    login_url    = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/saml2"
    logout_url   = "https://login.microsoftonline.com/${data.azuread_client_config.current.tenant_id}/saml2"
    entity_id    = "https://sts.windows.net/${data.azuread_client_config.current.tenant_id}/"
    certificate = {
      thumbprint = azuread_service_principal_token_signing_certificate.this[0].thumbprint
      end_date   = azuread_service_principal_token_signing_certificate.this[0].end_date
    }
  } : null
}

output "saml_certificate_value" {
  description = <<-EOT
    The SAML signing certificate, PEM-encoded without the header and footer
    lines, for a service provider that imports the certificate instead of
    reading federation metadata. Null when `service_principal.saml` is unset.

    It is the public certificate. It is sensitive only because the provider
    marks the attribute so, and it is kept out of `saml` so that output stays
    readable in plans.
  EOT

  sensitive = true
  value     = var.service_principal.saml != null ? azuread_service_principal_token_signing_certificate.this[0].value : null
}

output "password" {
  description = "The client secret's `key_id`, `value` and `end_date`, or null when `password` is unset."
  sensitive   = true
  value = var.password != null ? {
    key_id   = azuread_application_password.this[0].key_id
    value    = azuread_application_password.this[0].value
    end_date = azuread_application_password.this[0].end_date
  } : null
}
