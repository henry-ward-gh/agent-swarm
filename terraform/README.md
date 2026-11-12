# terraform

Creates the cluster and bootstraps Argo CD; everything inside the cluster is owned by [`gitops/`](../gitops/) ([ADR 0004](../docs/adr/0004-two-stage-terraform-secrets-generated-in-cluster.md), [ADR 0005](../docs/adr/0005-self-managed-argocd-terraform-owned-root.md)).

```
modules/
  cluster-kind/        kind cluster with Tetragon's mounts on every node; outputs the cluster-agnostic `kubernetes` object
  argocd-bootstrap/    installs Argo CD once (then ignores it) + the Terraform-owned root app → gitops/root
envs/kind/
  cluster/             stage 1 — local state
  bootstrap/           stage 2 — reads stage 1's state, configures helm from it
```

Two stages, applied in order, because configuring a provider from a cluster created in the same apply is unreliable. Providers are configured only in env roots. A future cloud target adds `modules/cluster-<cloud>` exposing the same `kubernetes` output.

## Use

```sh
task up                                  # both stages + load the Mock Agent image; Argo CD follows main
task up TARGET_REVISION=my-branch        # follow a pushed branch instead (Argo CD pulls from GitHub)
task argocd:ui                           # admin password + http://localhost:8080
task down                                # delete the cluster and local state
task tf:test                             # module tests with mocked providers — no cluster needed
```

Argo CD's chart (name, repo, version) comes from [`gitops/root/values.yaml`](../gitops/root/values.yaml) and its values from [`gitops/platform/argocd/values.yaml`](../gitops/platform/argocd/values.yaml) — the files the self-managed Argo CD app must also use.

## CI (`.github/workflows/terraform.yml`)

- **static** — `init -lockfile=readonly` + `validate` everywhere, module tests, `plan` of the cluster stage.
- **trivy** — IaC misconfiguration scan (HIGH/CRITICAL fail).
- **up** — real `task up` on kind, then asserts Argo CD's root app is Synced/Healthy at the commit under test.

`fmt` and `tflint` run via pre-commit in the `lint` workflow. Lock files are committed with `zh:` hashes for every published platform and `h1:` hashes for linux/darwin × amd64/arm64, so `init -lockfile=readonly` works on CI runners and Macs.
