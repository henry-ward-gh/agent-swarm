# gitops

Everything inside the cluster, deployed by Argo CD ([ADR 0005](../docs/adr/0005-self-managed-argocd-terraform-owned-root.md)).

| Path | What |
|---|---|
| [`root/`](root/) | The app-of-apps chart the Terraform-owned root app points at. It receives `targetRevision`, `repoURL` and `imageTag`; every child Application it renders must use them, so the whole cluster follows one revision. It renders `root-info` (a ConfigMap recording those values, which CI checks) and one Application per entry in `values.yaml`'s `platform:` map — self-managed Argo CD (`prune: false`), Tetragon, the mittwald secret-generator, the [`outside-world`](platform/outside-world/) stand-ins and the `demo` Swarm — ordered by sync wave (CRD providers first). Entry keys: `wave`, `namespace`, `prune` (default true), then either `repoURL`/`chart`/`version`/`values` for an upstream chart, `path`/`values` (and `followImageTag`, which sets `global.image.tag` to `imageTag`) for a chart in this repo, or, for Argo CD, `valuesFile`; an optional `ignoreDifferences` is passed through to the Application. Its `values.yaml` also pins Argo CD's own chart. |
| [`platform/argocd/values.yaml`](platform/argocd/values.yaml) | Argo CD's chart values — read by the Terraform bootstrap, and used by the self-managed Argo CD app. |
| [`platform/outside-world/`](platform/outside-world/) | In-cluster stand-ins for the Outside World: `approved-api` (an LLM API stand-in on every allowlist, pinned ClusterIP) and `exfil-sink` (on none; `GET /received` shows what reached it). |
