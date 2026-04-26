output "country" {
  description = "Regulatory-domain country code in effect for the VDOM, read back from the resource. Useful to confirm the setting applied before wtp-profiles inherit it via `ap_country = \"--\"`."
  value       = fortios_wirelesscontroller_setting.this.country
}
