# gitops

Everything inside the cluster, deployed by Argo CD ([ADR 0005](../docs/adr/0005-self-managed-argocd-terraform-owned-root.md)).

| Path | What |
|---|---|
| [`root/`](root/) | The app-of-apps chart the Terraform-owned root app points at. It receives `targetRevision`, `repoURL` and `imageTag`; every child Application it renders must use them, so the whole cluster follows one revision. It renders `root-info` (a ConfigMap recording those values, which CI checks) and one Application per entry in `values.yaml`'s `platform:` map — self-managed Argo CD (`prune: false`), Tetragon and the mittwald secret-generator — ordered by sync wave (CRD providers first). A platform entry may set `ignoreDifferences`. Its `values.yaml` also pins Argo CD's own chart. |
| [`platform/argocd/values.yaml`](platform/argocd/values.yaml) | Argo CD's chart values — read by the Terraform bootstrap, and used by the self-managed Argo CD app. |
