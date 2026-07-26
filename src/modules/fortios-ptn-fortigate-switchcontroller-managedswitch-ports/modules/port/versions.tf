terraform {
  required_version = ">= 1.15"

  required_providers {
    restful = {
      source  = "magodo/restful"
      version = ">= 0.25.2, < 1.0"
    }
  }
}
