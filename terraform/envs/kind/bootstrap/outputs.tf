output "argocd_namespace" {
  description = "Namespace Argo CD runs in."
  value       = module.argocd.namespace
}

output "target_revision" {
  description = "Revision the root app follows."
  value       = module.argocd.target_revision
}
