terraform {
  required_version = ">= 1.15"

  required_providers {
    github = {
      source  = "integrations/github"
      version = ">= 6.13, < 7.0"
    }
  }
}
