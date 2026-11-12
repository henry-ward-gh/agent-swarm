mock_provider "helm" {}

variables {
  repo_url             = "https://github.com/henry-ward-gh/agent-swarm.git"
  target_revision      = "0123abcd"
  image_tag            = "0123abcd"
  argocd_chart_version = "9.7.1"
  argocd_values        = "configs:\n  params:\n    server.insecure: true\n"
}

run "installs_the_pinned_argocd_chart_with_shared_values" {
  command = plan

  assert {
    condition     = helm_release.argocd.chart == "argo-cd" && helm_release.argocd.version == "9.7.1"
    error_message = "Argo CD must be installed from the argo-cd chart at the version read from gitops/."
  }

  assert {
    condition     = helm_release.argocd.namespace == "argocd" && helm_release.argocd.create_namespace
    error_message = "Argo CD belongs in its own argocd namespace."
  }

  assert {
    condition     = length(helm_release.argocd.values) == 1 && helm_release.argocd.values[0] == var.argocd_values
    error_message = "Argo CD values must be exactly the shared gitops/ values file."
  }
}

run "root_app_tracks_the_given_revision_and_repo" {
  command = plan

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.source.repoURL == "https://github.com/henry-ward-gh/agent-swarm.git"
    error_message = "Root app must pull from repo_url."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.source.targetRevision == "0123abcd"
    error_message = "Root app must follow target_revision."
  }

  assert {
    condition     = yamldecode(helm_release.root.values[0]).applications.root.source.path == "gitops/root"
    error_message = "Root app must point at the gitops/root chart."
  }
}

run "root_app_hands_revision_repo_and_image_tag_to_children" {
  command = plan

  assert {
    condition = yamldecode(helm_release.root.values[0]).applications.root.source.helm.valuesObject == {
      targetRevision = "0123abcd"
      repoURL        = "https://github.com/henry-ward-gh/agent-swarm.git"
      imageTag       = "0123abcd"
    }
    error_message = "gitops/root must receive targetRevision, repoURL and imageTag so every child follows them."
  }
}

run "root_app_syncs_automatically" {
  command = plan

  assert {
    condition = yamldecode(helm_release.root.values[0]).applications.root.syncPolicy.automated == {
      prune    = true
      selfHeal = true
    }
    error_message = "Root app must auto-sync with prune and self-heal."
  }
}

run "root_app_is_installed_after_argocd" {
  command = plan

  assert {
    condition     = helm_release.root.chart == "argocd-apps" && helm_release.root.namespace == "argocd"
    error_message = "Root app comes from the argocd-apps chart in the argocd namespace."
  }
}

run "rejects_non_https_repo_url" {
  command = plan

  variables {
    repo_url = "git@github.com:henry-ward-gh/agent-swarm.git"
  }

  expect_failures = [var.repo_url]
}

run "rejects_empty_target_revision" {
  command = plan

  variables {
    target_revision = ""
  }

  expect_failures = [var.target_revision]
}
