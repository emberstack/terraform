# =============================================================================
# FORTIGATE SYSTEM SAML (fortios_system_saml)
# =============================================================================
# Administrator SSO with the FortiGate as SAML service provider, so `role` is
# hardcoded. The identity-provider role, used for Security Fabric SSO, needs the
# `service_providers` sub-table, which is not exposed; left unconfigured, the
# provider neither reads nor sends it.
#
# `system saml` is a singleton: create and update both write it, and destroy
# sends `null` for every managed attribute, which FortiOS resets to its
# defaults — `status` included, so destroy turns admin SSO off.
#
# FortiOS derives the SP endpoints (`portal_url`, `single_sign_on_url`,
# `single_logout_url`) from `server_address`. They are computed in the
# provider, so leaving them unset does not diff; read them from the outputs.
#
# A write that changes `server_address` also makes FortiOS replace `entity_id`
# with one it generates (`http://<server_address>/metadata/`), even when
# `entity_id` is sent in the same request. The first apply, and any apply that
# moves the server address, therefore leaves an `entity_id` diff; a second
# apply settles it, because `server_address` no longer changes.
# =============================================================================

resource "fortios_system_saml" "this" {
  status = var.status
  role   = "service-provider"

  server_address     = var.server_address
  entity_id          = var.entity_id
  cert               = var.cert
  binding_protocol   = var.binding_protocol
  default_login_page = var.default_login_page
  default_profile    = var.default_profile

  idp_entity_id          = var.idp_entity_id
  idp_single_sign_on_url = var.idp_single_sign_on_url
  idp_single_logout_url  = var.idp_single_logout_url
  idp_cert               = var.idp_cert

  require_signed_resp_and_asrt = var.require_signed_resp_and_asrt
  tolerance                    = var.tolerance
  life                         = var.life
}
