# gitops

Everything inside the cluster, deployed by Argo CD ([ADR 0005](../docs/adr/0005-self-managed-argocd-terraform-owned-root.md)).

| Path | What |
|---|---|
| [`root/`](root/) | The app-of-apps chart the Terraform-owned root app points at. It receives `targetRevision`, `repoURL` and `imageTag`; every child Application it renders must use them, so the whole cluster follows one revision. Today it renders only `root-info` (a ConfigMap recording those values, which CI checks); the platform apps — self-managed Argo CD, Tetragon, secret-generator — arrive with [issue #18](https://github.com/henry-ward-gh/agent-swarm/issues/18). Its `values.yaml` also pins Argo CD's own chart. |
| [`platform/argocd/values.yaml`](platform/argocd/values.yaml) | Argo CD's chart values — read by the Terraform bootstrap, and to be used by the self-managed Argo CD app. |
