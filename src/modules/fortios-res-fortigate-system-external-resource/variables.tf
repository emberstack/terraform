variable "name" {
  description = "Name of the external resource (threat feed) entry. This is the resource mkey and how the feed is referenced from address groups, web filters and policies."
  type        = string
}

variable "type" {
  description = "Kind of feed being consumed, which determines where the entries can be referenced. Commonly `category`, `address`, `domain` or `malware`; newer firmware accepts additional types."
  type        = string
  default     = "domain"
}

variable "category" {
  description = "Numeric user-resource category ID the feed's entries are filed under. FortiOS uses the 192-221 range for user-defined threat-feed categories; the default `193` is an arbitrary pick from that range, so give each feed a distinct ID."
  type        = number
  default     = 193
}

variable "resource" {
  description = "URL the FortiGate fetches the feed from (for example `https://example.com/blocklist.txt`)."
  type        = string
}

variable "refresh_rate" {
  description = "How often, in minutes, the FortiGate re-downloads the feed."
  type        = number
  default     = 60
}

variable "status" {
  description = "Whether the feed is active. One of `enable` or `disable`."
  type        = string
  default     = "enable"
}

variable "comments" {
  description = "Free-text comment stored on the external resource entry."
  type        = string
  default     = ""
}
