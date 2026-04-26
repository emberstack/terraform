variable "name" {
  description = "Repository name, unique within the owning account or organization. Renaming an existing repository updates it in place; GitHub redirects the old URL."
  type        = string
  nullable    = false
}

variable "description" {
  description = "Short repository description shown on the repository page and in search results."
  type        = string
  default     = ""
  nullable    = false
}

variable "visibility" {
  description = "Repository visibility. `internal` is only available to organizations on GitHub Enterprise. Narrowing visibility on an existing repository does not remove existing forks."
  type        = string
  default     = "private"
  nullable    = false

  validation {
    condition     = contains(["private", "internal", "public"], var.visibility)
    error_message = "Visibility must be one of: private, internal, public."
  }
}

variable "default_branch" {
  description = "Name of the branch to set as the repository default. The branch must already exist — this module does not create it, so a brand-new empty repository has nothing to point at."
  type        = string
  default     = "main"
  nullable    = false
}

variable "allow_auto_merge" {
  description = "Allow pull requests to be queued for automatic merge once all required checks and approvals pass."
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_update_branch" {
  description = "Show the \"Update branch\" button on pull requests whose head branch is behind the base branch."
  type        = bool
  default     = false
  nullable    = false
}

variable "delete_branch_on_merge" {
  description = "Automatically delete the head branch after a pull request is merged."
  type        = bool
  default     = false
  nullable    = false
}

variable "allow_merge_commit" {
  description = "Permit merging pull requests with a merge commit. At least one of the three merge strategies must remain enabled."
  type        = bool
  default     = true
  nullable    = false
}

variable "allow_rebase_merge" {
  description = "Permit merging pull requests by rebasing. At least one of the three merge strategies must remain enabled."
  type        = bool
  default     = true
  nullable    = false
}

variable "allow_squash_merge" {
  description = "Permit merging pull requests by squashing. At least one of the three merge strategies must remain enabled."
  type        = bool
  default     = true
  nullable    = false
}

variable "merge_commit_title" {
  description = "Default title for merge commits. `PR_TITLE` uses the pull request title; `MERGE_MESSAGE` uses GitHub's classic \"Merge pull request #n\" form."
  type        = string
  default     = "MERGE_MESSAGE"
  nullable    = false
}

variable "merge_commit_message" {
  description = "Default body for merge commits: `PR_BODY`, `PR_TITLE`, or `BLANK`."
  type        = string
  default     = "PR_TITLE"
  nullable    = false
}

variable "squash_merge_commit_title" {
  description = "Default title for squash-merge commits: `PR_TITLE`, or `COMMIT_OR_PR_TITLE` to use the sole commit's message when the PR has exactly one commit."
  type        = string
  default     = "PR_TITLE"
  nullable    = false
}

variable "squash_merge_commit_message" {
  description = "Default body for squash-merge commits: `PR_BODY`, `COMMIT_MESSAGES` (concatenated commit messages), or `BLANK`."
  type        = string
  default     = "COMMIT_MESSAGES"
  nullable    = false
}

variable "has_issues" {
  description = "Enable the built-in issue tracker. Disabling hides existing issues rather than deleting them."
  type        = bool
  default     = true
  nullable    = false
}

variable "has_projects" {
  description = "Enable repository-scoped (classic) projects."
  type        = bool
  default     = false
  nullable    = false
}

variable "has_wiki" {
  description = "Enable the repository wiki."
  type        = bool
  default     = false
  nullable    = false
}

variable "variables" {
  description = "Repository-level GitHub Actions variables, keyed by variable name. Values are plaintext and readable by any workflow in the repository — never put credentials here, use `secrets`."
  type        = map(string)
  default     = {}
  nullable    = false
}

variable "secrets" {
  description = "Repository-level GitHub Actions secrets, keyed by secret name. Values are submitted as plaintext and are therefore persisted in Terraform state — protect the state backend accordingly. GitHub itself never returns them, so out-of-band changes are not detected."
  type        = map(string)
  default     = {}
  nullable    = false
  sensitive   = true
}

variable "rulesets" {
  description = <<-EOT
    Repository rulesets, keyed by ruleset name. Each entry:
      - `enforcement`   — `active`, `evaluate` (dry-run, reports without blocking), or `disabled`.
      - `target`        — what the ruleset applies to: `branch`, `tag`, or `push`.
      - `conditions`    — `ref_name.include` / `.exclude` patterns. Supports the `~ALL` and
                          `~DEFAULT_BRANCH` meta-refs alongside `refs/heads/*` globs.
      - `bypass_actors` — who may bypass the rules. `actor_type` is one of `RepositoryRole`,
                          `Team`, `Integration`, or `OrganizationAdmin`; `bypass_mode` is
                          `always` or `pull_request`.
      - `rules`         — the enforced rules. `deletion`, `non_fast_forward`,
                          `required_linear_history` and `creation` are simple toggles; the
                          nested objects configure pull-request review requirements, required
                          status checks, commit message patterns, and Copilot code review.

    Omitting a nested rule object leaves that rule unset rather than disabling it.
  EOT
  type = map(object({
    enforcement = optional(string, "active")
    target      = optional(string, "branch")
    conditions = optional(object({
      ref_name = object({
        include = list(string)
        exclude = optional(list(string), [])
      })
    }))
    bypass_actors = optional(list(object({
      actor_id    = optional(number)
      actor_type  = string
      bypass_mode = optional(string, "always")
    })), [])
    rules = object({
      deletion                = optional(bool, false)
      non_fast_forward        = optional(bool, false)
      required_linear_history = optional(bool, false)
      creation                = optional(bool, false)
      pull_request = optional(object({
        required_approving_review_count   = optional(number, 1)
        dismiss_stale_reviews_on_push     = optional(bool, false)
        require_code_owner_review         = optional(bool, false)
        require_last_push_approval        = optional(bool, false)
        required_review_thread_resolution = optional(bool, false)
        allowed_merge_methods             = optional(list(string), [])
      }))
      required_status_checks = optional(object({
        strict_required_status_checks_policy = optional(bool, false)
        do_not_enforce_on_create             = optional(bool, false)
        required_checks = list(object({
          context        = string
          integration_id = optional(number)
        }))
      }))
      commit_message_pattern = optional(object({
        operator = optional(string, "starts_with")
        pattern  = string
        name     = optional(string)
        negate   = optional(bool, false)
      }))
      copilot_code_review = optional(object({
        review_on_push             = optional(bool, true)
        review_draft_pull_requests = optional(bool, false)
      }))
    })
  }))
  default  = {}
  nullable = false
}
