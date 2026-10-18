variable "client_id" {
  description = <<-EOT
    Client (application) ID of the application to instantiate a service principal
    for. The application is registered elsewhere — for a Microsoft first-party
    application this is Microsoft's published ID, e.g.
    `2565bd9d-da50-47d4-8b85-4c97f669dc36` for Entra Domain Services' *Domain
    Controller Services*.

    Changing it replaces the service principal, which `prevent_destroy` blocks.
  EOT

  type     = string
  nullable = false

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.client_id))
    error_message = "client_id must be a UUID."
  }
}

variable "use_existing" {
  description = <<-EOT
    Adopt a service principal that already exists for `client_id` instead of
    failing on the duplicate. Needed whenever one was created outside Terraform —
    by the portal, by a service on first use, or by hand.

    Adoption does not need an import, and it is not exclusive: nothing stops a
    second configuration from adopting the same object. Manage each service
    principal from one place.
  EOT

  type     = bool
  default  = false
  nullable = false
}

variable "account_enabled" {
  description = "Whether the service principal is enabled. When false, no user can sign in to the application in this tenant, even an assigned one."

  type     = bool
  default  = true
  nullable = false
}

variable "app_role_assignment_required" {
  description = "When true, only users and groups assigned to the service principal can obtain tokens for the application."

  type     = bool
  default  = false
  nullable = false
}

variable "description" {
  description = <<-EOT
    Description shown to end users in My Apps. Managed: null clears a description
    set elsewhere.
  EOT

  type    = string
  default = null

  validation {
    condition     = var.description == null || length(coalesce(var.description, "x")) <= 1024
    error_message = "description must be 1024 characters or fewer."
  }
}

variable "notes" {
  description = "Free-text operational notes on the service principal. Managed: null clears notes set elsewhere."

  type    = string
  default = null
}

variable "owners" {
  description = <<-EOT
    Owners of the service principal. Map of stable key to either an Entra object
    ID (UUID) or a user principal name (UPN, resolved through Graph at plan time).

    Authoritative: an empty map removes owners added elsewhere.
  EOT

  type     = map(string)
  default  = {}
  nullable = false

  validation {
    condition = alltrue([
      for k, v in var.owners :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v)) ||
      can(regex("^[^@[:space:]]+@[^@[:space:]]+\\.[^@[:space:]]+$", v))
    ])
    error_message = "Each value in owners must be either a valid Entra object ID (UUID) or a user principal name (UPN, e.g. user@example.com)."
  }
}

variable "tags" {
  description = <<-EOT
    Tags on the service principal. Null leaves the existing tags alone — what a
    first-party service principal should usually get, since Microsoft sets its
    own. A set replaces them all.
  EOT

  type    = set(string)
  default = null
}
