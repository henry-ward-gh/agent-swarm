output "namespace" {
  description = "Namespace Argo CD runs in."
  value       = var.namespace
}

output "target_revision" {
  description = "Revision the root app follows."
  value       = var.target_revision
}
