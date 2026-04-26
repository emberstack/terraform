terraform {
  required_version = ">= 1.15"
  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.9, < 4.0"
    }
  }
}

provider "azuread" {}

module "ops_groups" {
  source = "../../"

  groups = {
    operators = {
      display_name = "ops-operators-test"
      description  = "Operations team — operator role"
      owners = {
        eve = "00000000-0000-0000-0000-000000000001"
      }
      members = {
        alice = "11111111-1111-1111-1111-111111111111"
        bob   = "22222222-2222-2222-2222-222222222222"
      }
    }

    readers = {
      display_name       = "ops-readers-test"
      description        = "Operations team — read-only role"
      assignable_to_role = false
      owners = {
        eve = "00000000-0000-0000-0000-000000000001"
      }
      members = {
        carol = "33333333-3333-3333-3333-333333333333"
      }
    }
  }
}

output "groups" {
  value = module.ops_groups.groups
}
