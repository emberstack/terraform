output "name" {
  description = "ServiceAccount name. Reference this rather than the input when a workload sets `serviceAccountName`, so the dependency edge orders the two."
  value       = kubernetes_service_account_v1.this.metadata[0].name
}

output "namespace" {
  description = "Namespace the ServiceAccount was created in."
  value       = kubernetes_service_account_v1.this.metadata[0].namespace
}

output "uid" {
  description = "Server-assigned UID. It is also what a federated credential's subject binds to conceptually — recreating the account under the same name issues a new UID, and any token minted for the old one is dead."
  value       = kubernetes_service_account_v1.this.metadata[0].uid
}

output "resource_version" {
  description = "Resource version as of the last read. It changes on every write to the object, including writes Terraform did not make, so it is a fingerprint to compare rather than something to wire into a trigger."
  value       = kubernetes_service_account_v1.this.metadata[0].resource_version
}
