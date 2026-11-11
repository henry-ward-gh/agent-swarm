# Argo CD manages itself; only the root app stays with Terraform

After the bootstrap stage installs Argo CD, an `argocd` Application in `gitops/` takes over Argo CD's chart version and values (Terraform keeps the helm release under `ignore_changes`). To stop a fresh cluster from installing one version and immediately syncing to another, the bootstrap module reads the chart version and values from that same file in `gitops/` — one source of truth.

The one exception is the root app: Terraform creates it (via `argocd-apps`) with a `target_revision`, and it is deliberately *not* self-managed, because Git's copy would pin it back to `main` and CI could never test a PR branch. The root points at a small Helm chart, `gitops/root`, which renders every child Application — Argo CD's own included — with `targetRevision: {{ .Values.targetRevision }}`, so a whole cluster follows one revision.

## Consequences

- Adding a platform or Swarm app means adding a template to `gitops/root`, never a hard-coded `targetRevision`.
- Children sync automatically with prune and self-heal, except Argo CD's own Application (`prune: false`) so a bad commit can't delete Argo CD.
