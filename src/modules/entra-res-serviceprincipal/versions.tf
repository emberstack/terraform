terraform {
  required_version = ">= 1.15"

  required_providers {
    azuread = {
      source  = "hashicorp/azuread"
      version = ">= 3.9, < 4.0"
    }
  }
}
