output "name" {
  description = "Object name, read back from the applied object rather than the input — referencing it is what orders a dependent behind this one."
  value       = kubernetes_manifest.this.object.metadata.name
}

output "namespace" {
  description = "Namespace the object was created in. **Null for a cluster-scoped kind** — a ClusterIssuer, ClusterRole or CRD has no namespace, and reading this without allowing for that is the usual way a caller trips over scope."
  value       = try(kubernetes_manifest.this.object.metadata.namespace, null)
}

output "api_version" {
  description = "The object's apiVersion as the server reports it. May differ from the input when the kind is served by several versions and the API server prefers another."
  value       = kubernetes_manifest.this.object.apiVersion
}

output "kind" {
  description = "The object's kind."
  value       = kubernetes_manifest.this.object.kind
}

output "object" {
  description = "The whole object as the API server returns it, including defaults it filled in and anything a controller wrote. This is the escape hatch a generic module needs: a caller wanting a field this module could not have predicted reads it here."
  value       = kubernetes_manifest.this.object
}
