variable "name" {
  description = "Name of the instance."
  type        = string

  validation {
    condition     = length(trimspace(var.name)) > 0
    error_message = "name must not be empty."
  }
}

variable "plan" {
  description = "Subscription plan, for example `bunny-3` or `squirrel-1`. The plan decides the backend, the node count and whether the instance is dedicated."
  type        = string

  validation {
    condition     = length(trimspace(var.plan)) > 0
    error_message = "plan must not be empty."
  }
}

variable "region" {
  description = "Region to host the instance in, as `<cloud>::<region>` — for example `azure-arm::westeurope`. Must match the VPC's region when `vpc_id` is set."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]+::[a-z0-9-]+$", var.region))
    error_message = "region must be <cloud>::<region>, for example azure-arm::westeurope."
  }
}

variable "nodes" {
  description = "Number of nodes in the cluster. The plan must support it. Null takes the plan's node count."
  type        = number
  default     = null

  validation {
    condition     = var.nodes == null || try(var.nodes >= 1 && floor(var.nodes) == var.nodes, false)
    error_message = "nodes must be a whole number of at least 1."
  }
}

variable "rmq_version" {
  description = "RabbitMQ version, for example `4.1.4`. Null takes the current default at creation and leaves upgrades to CloudAMQP."
  type        = string
  default     = null
}

variable "tags" {
  description = "Tags on the instance. CloudAMQP tags are plain strings, not key/value pairs."
  type        = list(string)
  default     = []
  nullable    = false
}

variable "vpc_id" {
  description = "Identifier of an existing CloudAMQP VPC to place the instance in — the `id` output of `cloudamqp-res-vpc`. Mutually exclusive with `vpc_subnet`."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_id == null || can(regex("^[0-9]+$", var.vpc_id))
    error_message = "vpc_id must be a numeric CloudAMQP VPC identifier."
  }
}

variable "vpc_subnet" {
  description = "Subnet in CIDR notation for a VPC that CloudAMQP creates alongside the instance. Mutually exclusive with `vpc_id`, which is preferred: a separately managed VPC outlives the instance."
  type        = string
  default     = null

  validation {
    condition     = var.vpc_subnet == null || can(cidrhost(var.vpc_subnet, 0))
    error_message = "vpc_subnet must be a CIDR block, for example 10.56.72.0/24."
  }

  validation {
    condition     = var.vpc_subnet == null || var.vpc_id == null
    error_message = "Set at most one of vpc_id and vpc_subnet."
  }
}

variable "preferred_az" {
  description = "Preferred availability zones, one entry per node. Null lets CloudAMQP place the nodes."
  type        = list(string)
  default     = null
}

variable "no_default_alarms" {
  description = "Skip the alarms CloudAMQP creates on a new instance."
  type        = bool
  default     = false
  nullable    = false
}

variable "keep_associated_vpc" {
  description = "Keep the instance's VPC when the instance is deleted. Only matters for a VPC created through `vpc_subnet`, or one nothing else uses."
  type        = bool
  default     = false
  nullable    = false
}

variable "private_link" {
  description = <<-EOT
    Private connectivity to the instance — Azure Private Link, AWS PrivateLink or GCP
    Private Service Connect. Fill the list for the instance's cloud:

    - `approved_subscriptions` — Azure subscription IDs allowed to connect.
    - `allowed_principals` — AWS principal ARNs allowed to connect.
    - `allowed_projects` — GCP project IDs allowed to connect.

    The instance must be in a VPC. Null leaves private connectivity off.
  EOT
  type = object({
    approved_subscriptions = optional(list(string))
    allowed_principals     = optional(list(string))
    allowed_projects       = optional(list(string))
  })
  default = null

  validation {
    condition = var.private_link == null || anytrue([
      length(coalesce(try(var.private_link.approved_subscriptions, null), [])) > 0,
      length(coalesce(try(var.private_link.allowed_principals, null), [])) > 0,
      length(coalesce(try(var.private_link.allowed_projects, null), [])) > 0,
    ])
    error_message = "private_link needs at least one entry in approved_subscriptions, allowed_principals or allowed_projects."
  }

  validation {
    condition = var.private_link == null || alltrue([
      for id in coalesce(try(var.private_link.approved_subscriptions, null), []) :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", id))
    ])
    error_message = "Every approved_subscriptions entry must be an Azure subscription ID (a GUID)."
  }

  validation {
    condition     = var.private_link == null || var.vpc_id != null || var.vpc_subnet != null
    error_message = "private_link needs the instance in a VPC: set vpc_id or vpc_subnet."
  }
}

variable "firewall" {
  description = <<-EOT
    The instance's firewall rule set, keyed by a stable name. The resource replaces the
    whole rule set, so every rule the instance should accept belongs here.

    - `ip` — source in CIDR notation, for example `203.0.113.0/24`.
    - `services` — predefined services to open: `AMQP`, `AMQPS`, `HTTPS`, `MQTT`, `MQTTS`,
      `STOMP`, `STOMPS`, `STREAM`, `STREAM_SSL`.
    - `ports` — custom ports to open.
    - `description` — defaults to the map key.

    Null manages no firewall at all.
  EOT
  type = object({
    rules = map(object({
      ip          = string
      description = optional(string)
      services    = optional(list(string), [])
      ports       = optional(list(number), [])
    }))
  })
  default = null

  validation {
    condition     = var.firewall == null || length(try(var.firewall.rules, {})) > 0
    error_message = "firewall needs at least one rule. Use null to leave the firewall unmanaged."
  }

  validation {
    condition     = var.firewall == null || alltrue([for r in values(try(var.firewall.rules, {})) : can(cidrhost(r.ip, 0))])
    error_message = "Every firewall rule ip must be in CIDR notation, for example 203.0.113.0/24."
  }

  validation {
    condition = var.firewall == null || alltrue(flatten([
      for r in values(try(var.firewall.rules, {})) : [
        for s in r.services : contains(["AMQP", "AMQPS", "HTTPS", "MQTT", "MQTTS", "STOMP", "STOMPS", "STREAM", "STREAM_SSL"], s)
      ]
    ]))
    error_message = "Firewall services must be among AMQP, AMQPS, HTTPS, MQTT, MQTTS, STOMP, STOMPS, STREAM and STREAM_SSL."
  }

  validation {
    condition = var.firewall == null || alltrue(flatten([
      for r in values(try(var.firewall.rules, {})) : [for p in r.ports : p >= 0 && p <= 65535 && floor(p) == p]
    ]))
    error_message = "Firewall ports must be whole numbers between 0 and 65535."
  }

  validation {
    condition     = var.firewall == null || alltrue([for r in values(try(var.firewall.rules, {})) : length(r.services) + length(r.ports) > 0])
    error_message = "Every firewall rule must open at least one service or port."
  }
}
