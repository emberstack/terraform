variable "status" {
  description = "Local disk logging. `enable` or `disable`. Required by the provider; a model or VM without a log disk cannot enable it."
  type        = string
  nullable    = false

  validation {
    condition     = contains(["enable", "disable"], var.status)
    error_message = "status must be enable or disable."
  }
}

variable "diskfull" {
  description = "What to do when the disk is full: `overwrite` the oldest logs or stop logging (`nolog`). `null` leaves it unmanaged; FortiOS defaults to `overwrite`."
  type        = string
  default     = null

  validation {
    condition     = var.diskfull == null || contains(["overwrite", "nolog"], var.diskfull)
    error_message = "diskfull must be overwrite or nolog."
  }
}

variable "ips_archive" {
  description = "Archive IPS packets to the local disk. `enable` or `disable`; `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.ips_archive == null || contains(["enable", "disable"], var.ips_archive)
    error_message = "ips_archive must be enable or disable."
  }
}

# -----------------------------------------------------------------------------
# Disk-full warning thresholds
# -----------------------------------------------------------------------------

variable "full_first_warning_threshold" {
  description = "Disk usage, as a percentage (1-98), that raises the first log-full warning. `null` leaves it unmanaged; FortiOS defaults to 75."
  type        = number
  default     = null

  validation {
    condition     = var.full_first_warning_threshold == null || (var.full_first_warning_threshold >= 1 && var.full_first_warning_threshold <= 98)
    error_message = "full_first_warning_threshold must be between 1 and 98."
  }
}

variable "full_second_warning_threshold" {
  description = "Disk usage, as a percentage (2-99), that raises the second log-full warning. `null` leaves it unmanaged; FortiOS defaults to 90."
  type        = number
  default     = null

  validation {
    condition     = var.full_second_warning_threshold == null || (var.full_second_warning_threshold >= 2 && var.full_second_warning_threshold <= 99)
    error_message = "full_second_warning_threshold must be between 2 and 99."
  }
}

variable "full_final_warning_threshold" {
  description = "Disk usage, as a percentage (3-100), that raises the final log-full warning. `null` leaves it unmanaged; FortiOS defaults to 95."
  type        = number
  default     = null

  validation {
    condition     = var.full_final_warning_threshold == null || (var.full_final_warning_threshold >= 3 && var.full_final_warning_threshold <= 100)
    error_message = "full_final_warning_threshold must be between 3 and 100."
  }
}

# -----------------------------------------------------------------------------
# Rolling
# -----------------------------------------------------------------------------

variable "max_log_file_size" {
  description = "Size in MB (1-100) at which a log file is rolled. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.max_log_file_size == null || (var.max_log_file_size >= 1 && var.max_log_file_size <= 100)
    error_message = "max_log_file_size must be between 1 and 100."
  }
}

variable "roll_schedule" {
  description = "How often log files are rolled on schedule: `daily` or `weekly` (on `roll_day`). `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.roll_schedule == null || contains(["daily", "weekly"], var.roll_schedule)
    error_message = "roll_schedule must be daily or weekly."
  }
}

variable "roll_day" {
  description = "Day of the week log files are rolled when `roll_schedule` is `weekly`, lower case (`sunday` ... `saturday`). `null` leaves it unmanaged."
  type        = string
  default     = null

  validation {
    condition     = var.roll_day == null || contains(["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"], var.roll_day)
    error_message = "roll_day must be a lower-case day of the week."
  }
}

variable "roll_time" {
  description = "Time of day (`hh:mm`) log files are rolled. Defaults to FortiOS's own `00:00` rather than `null`: the provider reads this back on every refresh, so leaving it unset diffs every plan."
  type        = string
  default     = "00:00"
  nullable    = false

  validation {
    condition     = can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", var.roll_time))
    error_message = "roll_time must be a 24-hour time in hh:mm form."
  }
}

# -----------------------------------------------------------------------------
# Retention and quotas
# -----------------------------------------------------------------------------

variable "maximum_log_age" {
  description = "Delete log files older than this many days (0-3650). `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.maximum_log_age == null || (var.maximum_log_age >= 0 && var.maximum_log_age <= 3650)
    error_message = "maximum_log_age must be between 0 and 3650."
  }
}

variable "log_quota" {
  description = "Disk space in MB reserved for logs. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.log_quota == null || var.log_quota >= 0
    error_message = "log_quota must not be negative."
  }
}

variable "dlp_archive_quota" {
  description = "Disk space in MB reserved for the DLP archive. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.dlp_archive_quota == null || var.dlp_archive_quota >= 0
    error_message = "dlp_archive_quota must not be negative."
  }
}

variable "report_quota" {
  description = "Disk space in MB reserved for the report database. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.report_quota == null || var.report_quota >= 0
    error_message = "report_quota must not be negative."
  }
}

variable "max_policy_packet_capture_size" {
  description = "Maximum size in MB of policy packet captures; 0 means unlimited. `null` leaves it unmanaged."
  type        = number
  default     = null

  validation {
    condition     = var.max_policy_packet_capture_size == null || var.max_policy_packet_capture_size >= 0
    error_message = "max_policy_packet_capture_size must not be negative."
  }
}
