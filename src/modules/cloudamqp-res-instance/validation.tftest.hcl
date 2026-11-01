# =============================================================================
# cloudamqp-res-instance tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not an account.
# =============================================================================

mock_provider "cloudamqp" {
  mock_resource "cloudamqp_instance" {
    defaults = {
      id = "1001"
    }
  }
}

variables {
  name   = "rmq-example"
  plan   = "bunny-3"
  region = "azure-arm::westeurope"
  vpc_id = "1000"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans_bare_instance" {
  command = plan

  assert {
    condition     = length(cloudamqp_vpc_connect.this) == 0 && length(cloudamqp_security_firewall.this) == 0
    error_message = "Neither child may exist when private_link and firewall are null."
  }

  assert {
    condition     = cloudamqp_instance.this.vpc_id == 1000
    error_message = "vpc_id must reach the instance as the VPC's identifier."
  }

  assert {
    condition     = output.private_link == null
    error_message = "The private_link output must be null without private_link."
  }
}

run "applies_private_link_and_firewall" {
  command = apply

  variables {
    private_link = {
      approved_subscriptions = ["00000000-0000-0000-0000-000000000000"]
    }
    firewall = {
      rules = {
        office = {
          ip       = "203.0.113.0/24"
          services = ["AMQPS", "HTTPS"]
        }
        monitoring = {
          ip          = "198.51.100.10/32"
          description = "Uptime probe"
          ports       = [15692]
        }
      }
    }
  }

  assert {
    condition     = cloudamqp_vpc_connect.this[0].region == "azure-arm::westeurope" && cloudamqp_vpc_connect.this[0].instance_id == 1001
    error_message = "The private link must target the instance, in the instance's region."
  }

  assert {
    condition     = toset([for r in cloudamqp_security_firewall.this[0].rules : r.description]) == toset(["office", "Uptime probe"])
    error_message = "A rule's description must default to its map key."
  }

  assert {
    condition     = output.private_link != null
    error_message = "The private_link output must be set when private_link is configured."
  }
}

# =============================================================================
# NEGATIVE — variable validation must reject bad input
# =============================================================================

run "rejects_both_vpc_inputs" {
  command = plan

  variables {
    vpc_subnet = "10.56.72.0/24"
  }

  expect_failures = [var.vpc_subnet]
}

run "rejects_empty_private_link" {
  command = plan

  variables {
    private_link = {}
  }

  expect_failures = [var.private_link]
}

run "rejects_non_guid_subscription" {
  command = plan

  variables {
    private_link = {
      approved_subscriptions = ["not-a-subscription"]
    }
  }

  expect_failures = [var.private_link]
}

run "rejects_private_link_without_vpc" {
  command = plan

  variables {
    vpc_id = null
    private_link = {
      approved_subscriptions = ["00000000-0000-0000-0000-000000000000"]
    }
  }

  expect_failures = [var.private_link]
}

run "rejects_unknown_service" {
  command = plan

  variables {
    firewall = {
      rules = {
        office = { ip = "203.0.113.0/24", services = ["AMQ"] }
      }
    }
  }

  expect_failures = [var.firewall]
}

run "rejects_rule_opening_nothing" {
  command = plan

  variables {
    firewall = {
      rules = {
        office = { ip = "203.0.113.0/24" }
      }
    }
  }

  expect_failures = [var.firewall]
}

run "rejects_bad_nodes" {
  command = plan

  variables {
    nodes = 0
  }

  expect_failures = [var.nodes]
}
