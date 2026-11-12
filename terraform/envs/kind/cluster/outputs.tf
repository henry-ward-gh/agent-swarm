output "kubernetes" {
  description = "Cluster-agnostic connection object consumed by the bootstrap stage."
  value       = module.cluster.kubernetes
  sensitive   = true
}

output "kubeconfig_path" {
  description = "Kubeconfig written by kind."
  value       = module.cluster.kubeconfig_path
}

output "context_name" {
  description = "kubectl context."
  value       = module.cluster.context_name
}

output "cluster_name" {
  description = "kind cluster name."
  value       = module.cluster.name
}
