output "policies" {
  description = <<-EOT
    Role management policies managed by this module, keyed by PIM role
    (`member` / `owner`). Each entry exposes `id` and `display_name`.
  EOT

  value = {
    for role, policy in azuread_group_role_management_policy.this : role => {
      id           = policy.id
      display_name = policy.display_name
    }
  }
}

output "eligibility" {
  description = <<-EOT
    Eligibility schedules, keyed by the `eligibility` input map key. Each entry
    exposes `id`, `principal_id` and `assignment_type`.
  EOT

  value = {
    for key, schedule in azuread_privileged_access_group_eligibility_schedule.this : key => {
      id              = schedule.id
      principal_id    = schedule.principal_id
      assignment_type = schedule.assignment_type
    }
  }
}

output "assignments" {
  description = <<-EOT
    Active assignment schedules, keyed by the `assignments` input map key. Each
    entry exposes `id`, `principal_id`, `assignment_type` and `status`.
  EOT

  value = {
    for key, schedule in azuread_privileged_access_group_assignment_schedule.this : key => {
      id              = schedule.id
      principal_id    = schedule.principal_id
      assignment_type = schedule.assignment_type
      status          = schedule.status
    }
  }
}
