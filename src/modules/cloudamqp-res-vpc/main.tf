# =============================================================================
# CLOUDAMQP VPC (cloudamqp_vpc)
# =============================================================================
# A standalone VPC that dedicated instances join through `vpc_id`. Owning it
# outside the instance lets several instances share one network, and lets an
# instance be replaced without the network — and the Private Link or peering
# built on it — going with it.
# =============================================================================

resource "cloudamqp_vpc" "this" {
  name   = var.name
  region = var.region
  subnet = var.subnet
  tags   = var.tags
}
