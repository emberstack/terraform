# -----------------------------------------------------------------------------
# Required
# -----------------------------------------------------------------------------

variable "name" {
  type        = string
  description = "The name of the policy definition. 1–64 chars, no `<`, `>`, `*`, `%`, `&`, `:`, `\\`, `?`, `/`, or control characters."
  nullable    = false

  validation {
    condition     = length(var.name) >= 1 && length(var.name) <= 64
    error_message = "name must be between 1 and 64 characters."
  }
}

variable "display_name" {
  type        = string
  description = "Human-readable display name shown in the portal."
  nullable    = false
}

variable "policy_rule" {
  type        = any
  description = <<-EOT
    The policy rule as an HCL value (object). Sent to ARM as a native object; the
    module does not `jsonencode` it.

    Typical shape:
    ```
    {
      if = { ... }
      then = {
        effect = "[parameters('effect')]"
        details = { ... }
      }
    }
    ```
  EOT
  nullable    = false
}

# -----------------------------------------------------------------------------
# Optional — scope
# -----------------------------------------------------------------------------

variable "management_group_id" {
  type        = string
  default     = null
  description = "ARM resource ID of the management group to scope the definition to. Leave null to scope to the current subscription."
}

# -----------------------------------------------------------------------------
# Optional — descriptive
# -----------------------------------------------------------------------------

variable "description" {
  type        = string
  default     = null
  description = "Long-form description shown in the portal."
}

variable "mode" {
  type        = string
  default     = "All"
  description = <<-EOT
    Policy mode. Common values:

    - `All`        — evaluates resource groups and resources (default).
    - `Indexed`    — evaluates only resources that support tags and location.
    - `Microsoft.Kubernetes.Data` — Azure Policy for AKS (Gatekeeper).
    - `Microsoft.KeyVault.Data`   — Azure Policy for Key Vault data plane.
    - `Microsoft.Network.Data`    — Azure Policy for Virtual Network Manager.
  EOT
  nullable    = false
}

variable "parameters" {
  type        = any
  default     = {}
  description = <<-EOT
    Parameter declarations as an HCL object. Empty map (default) means no parameters.

    Each entry shape:
    ```
    effect = {
      type = "String"
      metadata = {
        displayName = "Effect"
        description = "Enable or disable the policy"
      }
      allowedValues = ["Audit", "Deny", "Disabled"]
      defaultValue  = "Audit"
    }
    ```
  EOT
  nullable    = false
}

variable "metadata" {
  type        = any
  default     = {}
  description = <<-EOT
    Metadata as an HCL object. Common keys: `category`, `version`. Empty map (default) sends no metadata.

    Example:
    ```
    {
      category = "Tags"
      version  = "1.0.0"
    }
    ```
  EOT
  nullable    = false
}
