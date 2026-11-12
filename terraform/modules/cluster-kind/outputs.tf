# The cluster-agnostic contract every cluster-* module exposes (ADR 0004):
# feed it straight into `provider "helm" { kubernetes = ... }`.
output "kubernetes" {
  description = "Connection details: host + CA, and either client cert/key (kind) or token/exec (cloud)."
  sensitive   = true
  value = {
    host                   = kind_cluster.this.endpoint
    cluster_ca_certificate = kind_cluster.this.cluster_ca_certificate
    client_certificate     = kind_cluster.this.client_certificate
    client_key             = kind_cluster.this.client_key
    token                  = null
    exec                   = null
  }
}

output "kubeconfig_path" {
  description = "Kubeconfig written by kind."
  value       = kind_cluster.this.kubeconfig_path
}

output "context_name" {
  description = "kubectl context for this cluster."
  value       = kind_cluster.this.context_name
}

output "name" {
  description = "Cluster name (for kind load / kind delete)."
  value       = kind_cluster.this.name
}
