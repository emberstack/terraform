# =============================================================================
# GITHUB REPOSITORY
# =============================================================================
# `prevent_destroy` is hardcoded: a repository holds the only copy of its
# issues, wiki and settings, so accidental replacement is unrecoverable.
# Removing a repo therefore requires editing this module, not just the caller.
#
# `has_downloads` is ignored — GitHub still returns a value for this retired
# feature, which otherwise produces a permanent diff.
# =============================================================================

resource "github_repository" "this" {
  name        = var.name
  description = var.description
  visibility  = var.visibility

  has_issues   = var.has_issues
  has_projects = var.has_projects
  has_wiki     = var.has_wiki

  allow_auto_merge       = var.allow_auto_merge
  allow_update_branch    = var.allow_update_branch
  delete_branch_on_merge = var.delete_branch_on_merge

  allow_merge_commit          = var.allow_merge_commit
  allow_rebase_merge          = var.allow_rebase_merge
  allow_squash_merge          = var.allow_squash_merge
  merge_commit_title          = var.merge_commit_title
  merge_commit_message        = var.merge_commit_message
  squash_merge_commit_title   = var.squash_merge_commit_title
  squash_merge_commit_message = var.squash_merge_commit_message

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [has_downloads]
  }
}

resource "github_branch_default" "this" {
  repository = github_repository.this.name
  branch     = var.default_branch
}

module "variables" {
  source     = "./modules/variable"
  repository = github_repository.this.name
  variables  = var.variables
}

module "secrets" {
  source     = "./modules/secret"
  repository = github_repository.this.name
  secrets    = var.secrets
}

module "rulesets" {
  source     = "./modules/ruleset"
  repository = github_repository.this.name
  rulesets   = var.rulesets
}
