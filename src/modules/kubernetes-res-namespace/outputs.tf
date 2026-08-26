output "name" {
  description = "Namespace name. Reference this rather than the input when passing the namespace to a workload, so the dependency edge orders the two."
  value       = kubernetes_namespace_v1.this.metadata[0].name
}

output "uid" {
  description = "Server-assigned UID. Changes when the namespace is deleted and recreated, which makes it the way to tell a recreated namespace from a persistent one."
  value       = kubernetes_namespace_v1.this.metadata[0].uid
}

output "resource_version" {
  description = "Resource version as of the last read. It changes on every write to the object, including writes Terraform did not make, so it is a fingerprint to compare — not something to wire into a `replace_triggered_by`, which would churn."
  value       = kubernetes_namespace_v1.this.metadata[0].resource_version
}

output "labels" {
  description = "Labels as they exist on the namespace."
  value       = kubernetes_namespace_v1.this.metadata[0].labels
}

output "annotations" {
  description = "Annotations as they exist on the namespace."
  value       = kubernetes_namespace_v1.this.metadata[0].annotations
}
