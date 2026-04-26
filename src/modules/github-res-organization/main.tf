# =============================================================================
# GITHUB ORGANIZATION
# =============================================================================
# Manages a GitHub organization's settings, Actions permissions, workflow
# defaults, and optionally provisions organization-level Actions variables
# and secrets via inline submodule calls.
# =============================================================================

data "github_organization" "this" {
  name = var.name
}

resource "github_organization_settings" "this" {
  billing_email                                            = var.billing_email
  name                                                     = coalesce(var.display_name, var.name)
  location                                                 = var.location
  blog                                                     = var.blog
  default_repository_permission                            = var.default_repository_permission
  members_can_create_repositories                          = var.members_can_create_repositories
  members_can_create_public_repositories                   = var.members_can_create_public_repositories
  members_can_create_private_repositories                  = var.members_can_create_private_repositories
  members_can_create_internal_repositories                 = var.members_can_create_internal_repositories
  members_can_fork_private_repositories                    = var.members_can_fork_private_repositories
  has_organization_projects                                = var.has_organization_projects
  has_repository_projects                                  = var.has_repository_projects
  dependabot_alerts_enabled_for_new_repositories           = var.dependabot_alerts_enabled_for_new_repositories
  dependabot_security_updates_enabled_for_new_repositories = var.dependabot_security_updates_enabled_for_new_repositories
  dependency_graph_enabled_for_new_repositories            = var.dependency_graph_enabled_for_new_repositories

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_actions_organization_permissions" "this" {
  allowed_actions      = var.allowed_actions
  enabled_repositories = var.enabled_repositories

  dynamic "enabled_repositories_config" {
    for_each = length(var.enabled_repository_ids) > 0 ? [1] : []
    content {
      repository_ids = var.enabled_repository_ids
    }
  }

  dynamic "allowed_actions_config" {
    for_each = var.allowed_actions_config != null ? [var.allowed_actions_config] : []
    content {
      github_owned_allowed = allowed_actions_config.value.github_owned_allowed
      verified_allowed     = allowed_actions_config.value.verified_allowed
      patterns_allowed     = allowed_actions_config.value.patterns_allowed
    }
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "github_actions_organization_workflow_permissions" "this" {
  organization_slug                = var.name
  default_workflow_permissions     = var.default_workflow_permissions
  can_approve_pull_request_reviews = var.can_approve_pull_request_reviews
}

module "variables" {
  source = "./modules/variable"

  variables = var.variables
}

module "secrets" {
  source = "./modules/secret"

  secrets = var.secrets
}
