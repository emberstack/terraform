variable "repository" {
  description = "Name of the repository the rulesets are applied to."
  type        = string
  nullable    = false
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
  nullable = false
}
