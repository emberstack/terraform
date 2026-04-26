variable "name" {
  description = "Name of the ARRP (Automatic Radio Resource Provisioning) profile. This is the FortiOS mkey — changing it replaces the object. Referenced by name from a WTP profile radio's `arrp_profile`."
  type        = string
}

variable "comment" {
  description = "Free-text comment stored on the ARRP profile object. Cosmetic only."
  type        = string
  default     = ""
}

variable "selection_period" {
  description = "Seconds of accumulated monitoring data considered when DARRP scores channels and picks a new one. Default `3600`."
  type        = number
  default     = 3600
}

variable "monitor_period" {
  description = "Seconds between radio channel measurements feeding the DARRP score. Default `300`."
  type        = number
  default     = 300
}

variable "weight_managed_ap" {
  description = "Relative weight given to the number of managed APs already using a channel when DARRP scores it. Higher values push radios further apart from FortiGate-managed neighbours. Default `50`."
  type        = number
  default     = 50
}

variable "weight_noise_floor" {
  description = "Relative weight given to measured noise floor when DARRP scores a channel. Higher values bias selection toward quieter channels. Default `40`."
  type        = number
  default     = 40
}

variable "weight_dfs_channel" {
  description = "Relative weight given to DFS channels when DARRP scores them. Only meaningful when `include_dfs_channel` is `enable`. Default `0`."
  type        = number
  default     = 0
}

variable "weight_channel_load" {
  description = "Relative weight given to measured channel utilization when DARRP scores a channel. Default `20`."
  type        = number
  default     = 20
}

variable "weight_rogue_ap" {
  description = "Relative weight given to the number of detected unmanaged/rogue APs on a channel when DARRP scores it. Default `10`."
  type        = number
  default     = 10
}

variable "weight_spectral_rssi" {
  description = "Relative weight given to spectral RSSI measurements when DARRP scores a channel. Default `40`."
  type        = number
  default     = 40
}

variable "weight_weather_channel" {
  description = "Relative weight given to weather-radar channels when DARRP scores them. Only meaningful when `include_weather_channel` is `enable`. Default `0`."
  type        = number
  default     = 0
}

variable "include_weather_channel" {
  description = "Whether DARRP may select weather-radar channels. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "include_dfs_channel" {
  description = "Whether DARRP may select DFS channels. One of `enable` or `disable`."
  type        = string
  default     = "disable"
}

variable "darrp_optimize" {
  description = "Seconds between periodic DARRP optimization runs. Default `86400` (once per day). Set to `0` to disable periodic optimization and rely on `darrp_optimize_schedules` instead."
  type        = number
  default     = 86400
}

variable "darrp_optimize_schedules" {
  description = "Names of existing firewall schedules during which DARRP optimization is allowed to run. Each entry becomes one `darrp_optimize_schedules` block; an empty list emits none."
  type        = list(string)
  default     = []
}
