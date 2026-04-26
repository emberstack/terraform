variable "repository" {
  description = "The repository name."
  type        = string
}

variable "name" {
  description = "The environment name."
  type        = string
}

variable "wait_timer" {
  description = "The amount of time to delay a job after the job is initially triggered (minutes)."
  type        = number
  default     = 0
}

variable "reviewers" {
  description = "The environment protection rule reviewers."
  type = object({
    users = optional(list(number), [])
    teams = optional(list(number), [])
  })
  default = null
}

variable "deployment_branch_policy" {
  description = "The deployment branch policy for the environment."
  type = object({
    protected_branches     = optional(bool, false)
    custom_branch_policies = optional(bool, false)
  })
  default = null
}

variable "variables" {
  description = "A map of environment variables to set."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "A map of environment secrets to set."
  type        = map(string)
  default     = {}
  sensitive   = true
}
