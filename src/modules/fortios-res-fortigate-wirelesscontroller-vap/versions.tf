terraform {
  required_version = ">= 1.15"

  required_providers {
    fortios = {
      source  = "fortinetdev/fortios"
      version = ">= 1.26, < 2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.9, < 4.0"
    }
  }
}
