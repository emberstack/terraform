variable "repository" {
  description = "The repository name."
  type        = string
}

variable "environment" {
  description = "The environment name."
  type        = string
}

variable "secrets" {
  description = "A map of environment secrets to set."
  type        = map(string)
  sensitive   = true
}
