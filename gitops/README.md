# gitops

Everything inside the cluster, deployed by Argo CD ([ADR 0005](../docs/adr/0005-self-managed-argocd-terraform-owned-root.md)).

| Path | What |
|---|---|
| [`root/`](root/) | The app-of-apps chart the Terraform-owned root app points at. Every child Application it renders uses `{{ .Values.targetRevision }}`, `repoURL` and `imageTag`, so the whole cluster follows one revision. Its `values.yaml` also pins Argo CD's own chart version. |
| [`platform/argocd/values.yaml`](platform/argocd/values.yaml) | Argo CD's chart values — read by the Terraform bootstrap and by the self-managed Argo CD app. |
