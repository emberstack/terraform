terraform {
  required_version = ">= 1.15"

  required_providers {
    fortios = {
      source  = "fortinetdev/fortios"
      version = ">= 1.26, < 2.0"
    }
  }
}
