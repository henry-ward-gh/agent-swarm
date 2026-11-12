# Installs Argo CD once, then hands it to Git (ADR 0005):
# - Argo CD itself becomes a self-managed Application in gitops/, so Terraform
#   ignores later changes to this release;
# - the root app stays Terraform-owned so CI can point it at any revision.
resource "helm_release" "argocd" {
  name             = "argocd"
  namespace        = var.namespace
  create_namespace = true
  repository       = var.chart_repository
  chart            = var.argocd_chart
  version          = var.argocd_chart_version
  values           = [var.argocd_values]
  wait             = true
  timeout          = 600

  lifecycle {
    ignore_changes = all
  }
}

locals {
  root_app = {
    applications = {
      root = {
        namespace = var.namespace
        project   = "default"
        source = {
          repoURL        = var.repo_url
          targetRevision = var.target_revision
          path           = "gitops/root"
          helm = {
            # gitops/root templates every child with these, so the whole
            # cluster follows one revision and one image tag.
            valuesObject = merge(
              {
                targetRevision = var.target_revision
                repoURL        = var.repo_url
                imageTag       = var.image_tag
              },
              var.tetragon_version == "" ? {} : { platform = { tetragon = { version = var.tetragon_version } } },
            )
          }
        }
        destination = {
          server    = "https://kubernetes.default.svc"
          namespace = var.namespace
        }
        syncPolicy = {
          automated = {
            prune    = true
            selfHeal = true
          }
        }
      }
    }
  }
}

resource "helm_release" "root" {
  name       = "root"
  namespace  = var.namespace
  repository = var.chart_repository
  chart      = "argocd-apps"
  version    = var.argocd_apps_chart_version
  values     = [yamlencode(local.root_app)]

  depends_on = [helm_release.argocd]
}
