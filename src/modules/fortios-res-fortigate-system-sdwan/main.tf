resource "fortios_system_sdwan" "this" {
  status = var.status

  dynamic "zone" {
    for_each = var.zones
    content {
      name = zone.value.name
    }
  }

  dynamic "members" {
    for_each = var.members
    content {
      seq_num   = members.value.seq_num
      interface = members.value.interface
      gateway   = members.value.gateway
      status    = members.value.status
      cost      = members.value.cost
      priority  = members.value.priority
    }
  }

  dynamic "health_check" {
    for_each = var.health_checks
    content {
      name                = health_check.value.name
      server              = join(" ", health_check.value.server)
      protocol            = health_check.value.protocol
      interval            = health_check.value.interval
      failtime            = health_check.value.failtime
      recoverytime        = health_check.value.recoverytime
      update_static_route = health_check.value.update_static_route

      dynamic "members" {
        for_each = health_check.value.members
        content {
          seq_num = members.value
        }
      }

      dynamic "sla" {
        for_each = health_check.value.sla
        content {
          id                       = sla.value.id
          link_cost_factor         = sla.value.link_cost_factor
          latency_threshold        = sla.value.latency_threshold
          jitter_threshold         = sla.value.jitter_threshold
          packetloss_threshold     = sla.value.packetloss_threshold
          mos_threshold            = sla.value.mos_threshold
          custom_profile_threshold = sla.value.custom_profile_threshold
          priority_in_sla          = sla.value.priority_in_sla
          priority_out_sla         = sla.value.priority_out_sla
        }
      }
    }
  }

  dynamic "service" {
    for_each = var.services
    content {
      id   = service.value.id
      name = service.value.name
      mode = service.value.mode

      dynamic "dst" {
        for_each = service.value.dst
        content {
          name = dst.value
        }
      }

      dynamic "src" {
        for_each = service.value.src
        content {
          name = src.value
        }
      }

      dynamic "priority_members" {
        for_each = service.value.priority_members
        content {
          seq_num = priority_members.value
        }
      }
    }
  }
}
