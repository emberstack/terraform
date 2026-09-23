terraform {
  # `ignore_body_changes` is a write-only argument and needs 1.11 or later; the
  # rest of the tree already sits above that.
  required_version = ">= 1.15"

  required_providers {
    azapi = {
      source  = "Azure/azapi"
      version = ">= 2.12, < 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9, < 4.0"
    }
  }
}
