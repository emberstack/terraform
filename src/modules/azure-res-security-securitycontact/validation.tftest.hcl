# =============================================================================
# azure-res-security-securitycontact tests
# =============================================================================
# `mock_provider` keeps the suite offline: negative runs abort during variable
# validation, and the positive runs need a resource graph but not a real
# subscription.
#
# Caveat: mocking bypasses AzAPI's own schema checks, so the positive runs cannot
# confirm ARM accepts a body. The variable validation blocks are the guard.
# =============================================================================

mock_provider "azapi" {
  mock_data "azapi_client_config" {
    defaults = {
      subscription_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

# =============================================================================
# POSITIVE — resource graph and outputs must actually evaluate
# =============================================================================

run "defaults" {
  command = plan

  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        emails              = ""
        isEnabled           = true
        notificationsByRole = { roles = ["Owner"], state = "On" }
        notificationsSources = [
          { minimalRiskLevel = "Critical", sourceType = "AttackPath" },
          { minimalSeverity = "High", sourceType = "Alert" },
        ]
      }
    })
    error_message = "Defaults must be the portal's: owners notified, High alerts, Critical attack paths, no phone."
  }

  assert {
    condition     = azapi_resource.this.name == "default" && azapi_resource.this.parent_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "The contact must be the subscription's `default`."
  }
}

run "custom" {
  command = plan

  variables {
    emails                   = ["secops@example.com", "oncall@example.com"]
    phone                    = "+40000000000"
    notify_roles             = ["Owner", "Contributor"]
    alert_minimal_severity   = "Medium"
    attack_path_minimal_risk = null
  }

  assert {
    condition = jsonencode(azapi_resource.this.body) == jsonencode({
      properties = {
        emails               = "secops@example.com;oncall@example.com"
        isEnabled            = true
        notificationsByRole  = { roles = ["Owner", "Contributor"], state = "On" }
        notificationsSources = [{ minimalSeverity = "Medium", sourceType = "Alert" }]
        phone                = "+40000000000"
      }
    })
    error_message = "Emails must be semicolon-joined, a null threshold dropped, and the phone sent when set."
  }
}

run "no_roles" {
  command = plan

  variables {
    notify_roles = []
  }

  assert {
    condition     = azapi_resource.this.body.properties.notificationsByRole.state == "Off"
    error_message = "An empty role list must turn role notifications off."
  }
}

# =============================================================================
# NEGATIVE — variable validation
# =============================================================================

run "rejects_joined_emails" {
  command = plan
  variables {
    emails = ["a@example.com;b@example.com"]
  }
  expect_failures = [var.emails]
}

run "rejects_bad_role" {
  command = plan
  variables {
    notify_roles = ["Reader"]
  }
  expect_failures = [var.notify_roles]
}

run "rejects_bad_severity" {
  command = plan
  variables {
    alert_minimal_severity = "Critical"
  }
  expect_failures = [var.alert_minimal_severity]
}

run "rejects_bad_risk" {
  command = plan
  variables {
    attack_path_minimal_risk = "Severe"
  }
  expect_failures = [var.attack_path_minimal_risk]
}
