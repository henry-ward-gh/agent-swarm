variable "repo_url" {
  description = "Git repo Argo CD pulls from. CI sets the PR's head repo so fork PRs work."
  type        = string

  validation {
    condition     = startswith(var.repo_url, "https://")
    error_message = "repo_url must be an https:// URL (the repo is public; no credentials)."
  }
}

variable "target_revision" {
  description = "Git revision every Application follows: a branch locally, the head SHA in CI."
  type        = string

  validation {
    condition     = length(trimspace(var.target_revision)) > 0
    error_message = "target_revision must not be empty."
  }
}

variable "image_tag" {
  description = "Mock Agent image tag handed down to Swarm apps."
  type        = string
  default     = "dev"
}

variable "argocd_chart_version" {
  description = "argo-cd chart version — read from gitops/ so the self-managed Argo CD app and this bootstrap agree (ADR 0005)."
  type        = string
}

variable "argocd_values" {
  description = "argo-cd chart values (YAML) — the same file the self-managed Argo CD app uses."
  type        = string
}

variable "argocd_apps_chart_version" {
  description = "argocd-apps chart version used to create the root app."
  type        = string
  default     = "2.0.8"
}

variable "chart_repository" {
  description = "Helm repository for argo-cd and argocd-apps."
  type        = string
  default     = "https://argoproj.github.io/argo-helm"
}

variable "namespace" {
  description = "Namespace for Argo CD and the root app."
  type        = string
  default     = "argocd"
}
