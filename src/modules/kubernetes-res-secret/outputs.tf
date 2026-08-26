output "name" {
  description = "Secret name. Reference this rather than the input when a workload mounts the Secret, so the dependency edge orders the two."
  value       = kubernetes_secret_v1.this.metadata[0].name
}

output "namespace" {
  description = "Namespace the Secret was created in."
  value       = kubernetes_secret_v1.this.metadata[0].namespace
}

output "uid" {
  description = "Server-assigned UID. Changes when the Secret is deleted and recreated, which is how an immutable Secret's content is replaced."
  value       = kubernetes_secret_v1.this.metadata[0].uid
}

output "labels" {
  description = "Labels as they exist on the Secret."
  value       = kubernetes_secret_v1.this.metadata[0].labels
}

output "annotations" {
  description = "Annotations as they exist on the Secret."
  value       = kubernetes_secret_v1.this.metadata[0].annotations
}

output "resource_version" {
  description = "Resource version as of the last read. It changes on every write to the object, including writes Terraform did not make, so it is a fingerprint to compare — not something to wire into a `replace_triggered_by`, which would churn."
  value       = kubernetes_secret_v1.this.metadata[0].resource_version
}

output "type" {
  description = "Secret type as applied."
  value       = kubernetes_secret_v1.this.type
}
