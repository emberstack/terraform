variable "repository" {
  description = "Name of the repository the secrets are created on."
  type        = string
  nullable    = false
}

variable "secrets" {
  description = "GitHub Actions secrets, keyed by secret name. Values are submitted as plaintext and are therefore persisted in Terraform state — protect the state backend accordingly. GitHub never returns secret values, so changes made outside Terraform are not detected."
  type        = map(string)
  nullable    = false
  sensitive   = true
}
