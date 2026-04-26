output "name" {
  description = "Schedule name as stored on the device — the value to reference from a firewall policy's `schedule`, a VAP `schedule`, or an ARRP `darrp_optimize_schedules` entry."
  value       = fortios_firewallschedule_recurring.this.name
}
