terraform {
  required_version = ">= 1.15"

  required_providers {
    cloudamqp = {
      source  = "cloudamqp/cloudamqp"
      version = ">= 1.52, < 2.0"
    }
  }
}
