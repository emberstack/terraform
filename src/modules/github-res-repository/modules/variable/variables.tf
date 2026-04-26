variable "repository" {
  description = "Name of the repository the Actions variables are created on."
  type        = string
  nullable    = false
}

variable "variables" {
  description = "GitHub Actions variables, keyed by variable name. Values are plaintext and readable by any workflow in the repository — never put credentials here, use the secret submodule."
  type        = map(string)
  nullable    = false
}
