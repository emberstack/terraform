resource "fortios_wirelesscontroller_mpskprofile" "this" {
  name                    = var.name
  mpsk_type               = var.mpsk_type
  mpsk_concurrent_clients = var.mpsk_concurrent_clients

  dynamic "mpsk_group" {
    for_each = var.groups
    content {
      name      = mpsk_group.key
      vlan_type = mpsk_group.value.vlan_type
      vlan_id   = mpsk_group.value.vlan_id

      dynamic "mpsk_key" {
        for_each = mpsk_group.value.keys
        content {
          name                         = mpsk_key.key
          passphrase                   = mpsk_key.value.passphrase
          sae_password                 = mpsk_key.value.sae_password
          key_type                     = mpsk_key.value.key_type
          mac                          = mpsk_key.value.mac
          concurrent_client_limit_type = mpsk_key.value.concurrent_client_limit_type
          concurrent_clients           = mpsk_key.value.concurrent_clients
          comment                      = mpsk_key.value.comment

          dynamic "mpsk_schedules" {
            for_each = mpsk_key.value.mpsk_schedules
            content {
              name = mpsk_schedules.value
            }
          }
        }
      }
    }
  }
}
