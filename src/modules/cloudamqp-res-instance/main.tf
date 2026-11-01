# =============================================================================
# CLOUDAMQP INSTANCE (cloudamqp_instance)
# =============================================================================
# A broker instance plus the two children that are meaningless without it and
# carry nothing but its ID: the private-connectivity endpoint service
# (`private_link`) and the public firewall (`firewall`).
#
# Unset optional arguments are passed as null so the provider's own defaults
# and computed values apply. `nodes` and `rmq_version` in particular are
# computed from the plan when left unset; pinning either here would turn a
# CloudAMQP-side change into a diff.
# =============================================================================

resource "cloudamqp_instance" "this" {
  name   = var.name
  plan   = var.plan
  region = var.region

  keep_associated_vpc = var.keep_associated_vpc
  no_default_alarms   = var.no_default_alarms
  nodes               = var.nodes
  preferred_az        = var.preferred_az
  rmq_version         = var.rmq_version
  tags                = var.tags
  vpc_id              = var.vpc_id
  vpc_subnet          = var.vpc_subnet
}

# -----------------------------------------------------------------------------
# Private link — AWS PrivateLink, Azure Private Link, GCP Private Service Connect
# -----------------------------------------------------------------------------
# The service end only. The consumer's endpoint is created in the consumer's
# cloud against `private_link.service_name`; on Azure that is a manual private
# endpoint connection that targets the name as an alias.

resource "cloudamqp_vpc_connect" "this" {
  count = var.private_link != null ? 1 : 0

  instance_id            = cloudamqp_instance.this.id
  region                 = var.region
  allowed_principals     = var.private_link.allowed_principals
  allowed_projects       = var.private_link.allowed_projects
  approved_subscriptions = var.private_link.approved_subscriptions
}

# -----------------------------------------------------------------------------
# Firewall
# -----------------------------------------------------------------------------
# The resource owns the instance's whole rule set. Left null, no firewall
# resource exists and the instance keeps whatever rules CloudAMQP gave it.

resource "cloudamqp_security_firewall" "this" {
  count = var.firewall != null ? 1 : 0

  instance_id = cloudamqp_instance.this.id

  dynamic "rules" {
    for_each = var.firewall.rules
    content {
      description = coalesce(rules.value.description, rules.key)
      ip          = rules.value.ip
      ports       = rules.value.ports
      services    = rules.value.services
    }
  }
}
