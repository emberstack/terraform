# =============================================================================
# GITHUB REPOSITORY ENVIRONMENT
# =============================================================================
# Reviewers and deployment branch policies are optional. Variables and secrets
# are delegated to submodules for independent lifecycle management.
# =============================================================================

resource "github_repository_environment" "this" {
  repository  = var.repository
  environment = var.name
  wait_timer  = var.wait_timer

  dynamic "reviewers" {
    for_each = var.reviewers != null ? [var.reviewers] : []
    content {
      users = reviewers.value.users
      teams = reviewers.value.teams
    }
  }

  dynamic "deployment_branch_policy" {
    for_each = var.deployment_branch_policy != null ? [var.deployment_branch_policy] : []
    content {
      protected_branches     = deployment_branch_policy.value.protected_branches
      custom_branch_policies = deployment_branch_policy.value.custom_branch_policies
    }
  }
}

module "variables" {
  source      = "./modules/variable"
  repository  = var.repository
  environment = github_repository_environment.this.environment
  variables   = var.variables
}

module "secrets" {
  source      = "./modules/secret"
  repository  = var.repository
  environment = github_repository_environment.this.environment
  secrets     = var.secrets
}
