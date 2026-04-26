terraform {
  required_version = ">= 1.15"

  required_providers {
    fortios = {
      source  = "fortinetdev/fortios"
      version = ">= 1.25, < 2.0"
    }
  }
}
