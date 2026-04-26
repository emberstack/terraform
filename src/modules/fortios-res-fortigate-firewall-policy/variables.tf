variable "policyid" {
  description = "Explicit policy ID (`policyid` mkey). Leave `null` to let FortiOS assign the next free ID. Pin it when policy ordering or external references matter — changing it later replaces the policy."
  type        = number
  default     = null
}

variable "name" {
  description = "Policy name shown in the FortiGate policy table."
  type        = string
}

variable "srcintf" {
  description = "Source interfaces the policy matches. Each entry becomes one `srcintf` block; names must resolve to an existing interface or zone (`any` matches all)."
  type        = list(string)
}

variable "dstintf" {
  description = "Destination interfaces the policy matches. Each entry becomes one `dstintf` block; names must resolve to an existing interface or zone (`any` matches all)."
  type        = list(string)
}

variable "srcaddr" {
  description = "Source firewall address / address-group names. Each entry becomes one `srcaddr` block. The objects must already exist on the device."
  type        = list(string)
  default     = ["all"]
}

variable "dstaddr" {
  description = "Destination firewall address / address-group names. Each entry becomes one `dstaddr` block. The objects must already exist on the device."
  type        = list(string)
  default     = ["all"]
}

variable "service" {
  description = "Firewall service / service-group names the policy matches. Each entry becomes one `service` block. Service names are case-sensitive on FortiOS (`ALL`, `HTTPS`, ...)."
  type        = list(string)
  default     = ["ALL"]
}

variable "groups" {
  description = "User groups required to match this policy. Each entry becomes one `groups` block. Leave empty for a policy with no user-group restriction."
  type        = list(string)
  default     = []
}

variable "action" {
  description = "What the FortiGate does with matching traffic. One of `accept`, `deny` or `ipsec`."
  type        = string
  default     = "accept"
}

variable "schedule" {
  description = "Name of the firewall schedule during which the policy is active. `always` is the built-in always-on schedule; any other value must reference an existing recurring or onetime schedule object."
  type        = string
  default     = "always"
}

variable "nat" {
  description = "Whether to source-NAT matching traffic to the outgoing interface address. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "status" {
  description = "Whether the policy is active. One of `enable` or `disable`; `disable` keeps the policy defined but skips it during matching."
  type        = string
  default     = "enable"
}

variable "logtraffic" {
  description = "Traffic logging level for the policy. One of `all` (log every session), `utm` (log only sessions with a UTM event) or `disable`."
  type        = string
  default     = "all"
}

variable "logtraffic_start" {
  description = "Whether to also emit a log entry when a session starts, not only when it closes. One of `enable` or `disable`. Only has an effect when `logtraffic` is not `disable`."
  type        = string
  default     = "enable"
}

variable "comments" {
  description = "Free-text comment stored on the policy."
  type        = string
  default     = ""
}

# "0" = inherit the global session-ttl; matches the FortiOS device default so unset policies don't perpetually diff (provider reports "0", not null).
variable "session_ttl" {
  description = "Per-policy session timeout in seconds, as a string. `\"0\"` inherits the global session-ttl and is the FortiOS device default — the provider reads back `\"0\"` rather than null, so this default avoids a perpetual diff."
  type        = string
  default     = "0"
}
