terraform {
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
