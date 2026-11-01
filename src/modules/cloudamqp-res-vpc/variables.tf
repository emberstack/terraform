variable "name" {
  description = "Name of the VPC."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "region" {
  description = "Region to host the VPC in, as `<cloud>::<region>` — for example `azure-arm::westeurope` or `amazon-web-services::eu-west-1`. Instances that join the VPC must use the same region."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+::[a-z0-9-]+$", var.region))
    error_message = "region must be <cloud>::<region>, for example azure-arm::westeurope."
  }
}

variable "subnet" {
  description = "The VPC's subnet in CIDR notation, for example `10.56.72.0/24`. Keep it clear of every network the VPC will be peered or privately linked with."
  type        = string

  validation {
    condition     = can(cidrhost(var.subnet, 0))
    error_message = "subnet must be a CIDR block, for example 10.56.72.0/24."
  }
}

variable "tags" {
  description = "Tags on the VPC. CloudAMQP tags are plain strings, not key/value pairs."
  type        = list(string)
  default     = []
  nullable    = false
}
