variable "emails" {
  type        = list(string)
  default     = []
  description = "Email addresses notified directly, on top of the roles in `notify_roles`. Sent to ARM semicolon-separated."
  nullable    = false

  validation {
    condition     = alltrue([for email in var.emails : can(regex("^[^@;\\s]+@[^@;\\s]+$", email))])
    error_message = "emails must be plain addresses, one per list entry, with no semicolons."
  }
}

variable "phone" {
  type        = string
  default     = null
  description = "Phone number for the contact. Null leaves it unset."
}

variable "enabled" {
  type        = bool
  default     = true
  description = "Whether notifications are sent at all. Default: true."
  nullable    = false
}

variable "notify_roles" {
  type        = list(string)
  default     = ["Owner"]
  description = <<-EOT
    Subscription roles whose holders are notified: `Owner`, `Contributor`,
    `ServiceAdmin`, `AccountAdmin`. Default: `["Owner"]`, as in the portal. An
    empty list turns role notifications off.
  EOT
  nullable    = false

  validation {
    condition     = alltrue([for role in var.notify_roles : contains(["AccountAdmin", "Contributor", "Owner", "ServiceAdmin"], role)])
    error_message = "notify_roles may contain only AccountAdmin, Contributor, Owner and ServiceAdmin."
  }
}

variable "alert_minimal_severity" {
  type        = string
  default     = "High"
  description = "Lowest security alert severity that is notified: `High`, `Medium` or `Low`. Default: `High`, as in the portal. Null stops alert notifications."

  validation {
    condition     = var.alert_minimal_severity == null || contains(["High", "Medium", "Low"], coalesce(var.alert_minimal_severity, "High"))
    error_message = "alert_minimal_severity must be High, Medium, Low or null."
  }
}

variable "attack_path_minimal_risk" {
  type        = string
  default     = "Critical"
  description = "Lowest attack path risk level that is notified: `Critical`, `High`, `Medium` or `Low`. Default: `Critical`. Null stops attack path notifications."

  validation {
    condition     = var.attack_path_minimal_risk == null || contains(["Critical", "High", "Medium", "Low"], coalesce(var.attack_path_minimal_risk, "Critical"))
    error_message = "attack_path_minimal_risk must be Critical, High, Medium, Low or null."
  }
}
