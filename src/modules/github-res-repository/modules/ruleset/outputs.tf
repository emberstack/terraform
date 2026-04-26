output "rulesets" {
  description = "Managed rulesets keyed by the input map key, each carrying its GitHub `name` and numeric `id`."
  value = { for key, ruleset in github_repository_ruleset.this : key => {
    name = ruleset.name
    id   = ruleset.ruleset_id
  } }
}
