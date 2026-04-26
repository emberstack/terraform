variable "administrative_unit_object_id" {
  description = "Object ID of the administrative unit to add members to."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", var.administrative_unit_object_id))
    error_message = "administrative_unit_object_id must be a valid Entra object ID (UUID)."
  }
}

variable "members" {
  description = "Map of members to add. The key is a stable identifier (used as the for_each key); the value is the member's Entra object ID."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.members :
      can(regex("^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", v))
    ])
    error_message = "Each value in members must be a valid Entra object ID (UUID)."
  }
}
