resource "fortios_user_saml" "this" {
  name = var.name

  # Service provider (FortiGate side)
  cert               = var.cert
  entity_id          = var.entity_id
  single_sign_on_url = var.single_sign_on_url
  single_logout_url  = var.single_logout_url
  digest_method      = var.digest_method

  # Identity provider (Entra / external IdP side)
  idp_entity_id          = var.idp_entity_id
  idp_single_sign_on_url = var.idp_single_sign_on_url
  idp_single_logout_url  = var.idp_single_logout_url
  idp_cert               = var.idp_cert

  # Attribute / claim mapping
  user_name  = var.user_name
  group_name = var.group_name
}
