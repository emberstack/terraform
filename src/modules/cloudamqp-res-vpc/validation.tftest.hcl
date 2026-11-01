# =============================================================================
# cloudamqp-res-vpc tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive run needs a resource graph but not an account.
# =============================================================================

mock_provider "cloudamqp" {}

variables {
  name   = "vpc-example"
  region = "azure-arm::westeurope"
  subnet = "10.56.72.0/24"
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "plans" {
  command = plan

  assert {
    condition     = cloudamqp_vpc.this.name == "vpc-example" && cloudamqp_vpc.this.subnet == "10.56.72.0/24"
    error_message = "The VPC must carry the configured name and subnet."
  }

  assert {
    condition     = length(cloudamqp_vpc.this.tags) == 0
    error_message = "tags must default to an empty list, not null."
  }
}

# =============================================================================
# NEGATIVE — variable validation must reject bad input
# =============================================================================

run "rejects_bare_region" {
  command = plan

  variables {
    region = "westeurope"
  }

  expect_failures = [var.region]
}

run "rejects_non_cidr_subnet" {
  command = plan

  variables {
    subnet = "10.56.72.0"
  }

  expect_failures = [var.subnet]
}

run "rejects_empty_name" {
  command = plan

  variables {
    name = " "
  }

  expect_failures = [var.name]
}
