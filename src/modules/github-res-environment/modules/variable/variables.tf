variable "repository" {
  description = "The repository name."
  type        = string
}

variable "environment" {
  description = "The environment name."
  type        = string
}

variable "variables" {
  description = "A map of environment variables to set."
  type        = map(string)
}
