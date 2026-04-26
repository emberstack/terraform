variable "name" {
  description = "Name of the MPSK (Multiple Pre-Shared Key) profile. This is the FortiOS mkey — changing it replaces the object. Referenced by name from a VAP's `mpsk_profile`."
  type        = string
}

variable "mpsk_type" {
  description = "Key exchange type the profile's keys are used with. One of `wpa2-personal`, `wpa3-sae`, or `wpa3-sae-transition`. Determines whether a key's `passphrase`, `sae_password`, or both are meaningful."
  type        = string
  default     = "wpa3-sae-transition"
}

variable "mpsk_concurrent_clients" {
  description = "Profile-wide cap on concurrent clients per MPSK key. `0` means unlimited. Individual keys can override this via `concurrent_client_limit_type` and `concurrent_clients`."
  type        = number
  default     = 0
}

variable "groups" {
  description = "Map of MPSK groups; each owns a VLAN binding + a map of keys."
  type = map(object({
    vlan_type = optional(string, "fixed-vlan")
    vlan_id   = number
    keys = map(object({
      passphrase                   = optional(string)
      sae_password                 = optional(string)
      key_type                     = optional(string, "wpa2-personal")
      mac                          = optional(string)
      concurrent_client_limit_type = optional(string, "default")
      concurrent_clients           = optional(number)
      mpsk_schedules               = optional(list(string), [])
      comment                      = optional(string, "")
    }))
  }))
  sensitive = true
  default   = {}
}
