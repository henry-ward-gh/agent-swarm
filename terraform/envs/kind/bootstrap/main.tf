# Stage 2 of 2: Argo CD + the root app, on the cluster stage 1 created.
# Separate applies because configuring a provider from a cluster created in
# the same apply is unreliable (ADR 0004).
data "terraform_remote_state" "cluster" {
  backend = "local"

  config = {
    path = "${path.module}/../cluster/terraform.tfstate"
  }
}

locals {
  k8s         = data.terraform_remote_state.cluster.outputs.kubernetes
  gitops      = "${path.module}/../../../../gitops"
  root_values = yamldecode(file("${local.gitops}/root/values.yaml"))
}

provider "helm" {
  kubernetes = {
    host                   = local.k8s.host
    cluster_ca_certificate = local.k8s.cluster_ca_certificate
    client_certificate     = local.k8s.client_certificate
    client_key             = local.k8s.client_key
    token                  = local.k8s.token
  }
}

module "argocd" {
  source = "../../../modules/argocd-bootstrap"

  repo_url             = var.repo_url
  target_revision      = var.target_revision
  image_tag            = var.image_tag
  chart_repository     = local.root_values.argocd.repoURL
  argocd_chart_version = local.root_values.argocd.version
  argocd_values        = file("${local.gitops}/platform/argocd/values.yaml")
}
