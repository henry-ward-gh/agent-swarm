# Terraform providers for kind, the Argo CD bootstrap, and state

Resolves #4. Researched 2026-11-11 against provider GitHub repos, their in-repo docs (the same Markdown the Terraform Registry shows), the Argo CD docs, and Terraform/OpenTofu release notes.

Standing decision this builds on: **Terraform owns the cluster and the Argo CD bootstrap. Argo CD (GitOps) owns everything else in the cluster.**

## TL;DR recommendation

| Concern | Pick | Why |
|---|---|---|
| kind cluster | `tehcyx/kind` (~> 0.13) | It is the only maintained kind provider. The older `kyma-incubator/kind` is archived. |
| Install Argo CD | `hashicorp/helm` (~> 3.3) → `argo-cd` chart from argo-helm | Official provider, actively released. Needs no CRDs at plan time. |
| Point Argo CD at this repo | A second `helm_release` of the `argocd-apps` chart that renders **one root Application** (app-of-apps) aimed at this repo's `gitops/` path | Avoids `kubernetes_manifest`, which needs a live cluster at plan time. Stays inside one provider. |
| `argoproj-labs/argocd` | **Don't use** for bootstrap | Its README says it is "not concerned with the installation/configuration of ArgoCD itself". It needs a reachable Argo CD API server. Keep it in reserve only if we later need Terraform-managed project tokens. |
| kubectl-style providers | Not needed | `alekc/kubectl` is healthy, but adding a third provider buys nothing over `argocd-apps`. `gavinbunney/kubectl` is effectively unmaintained. |
| State: local / CI (kind) | Local backend. The state is as throwaway as the cluster. | The kind cluster dies with the laptop session or the CI runner, so remote state would point at nothing. |
| State: cloud (later) | Remote backend, e.g. S3 with `use_lockfile = true` (or GCS/azurerm), in its own root module | Native S3 locking is GA in Terraform 1.11 and OpenTofu 1.10. DynamoDB is no longer needed. |
| Terraform vs OpenTofu | Doesn't matter for these choices. Pin both via `required_version`. | All four providers are published to both registries at their current versions. |

## 1. Creating the kind cluster

### `tehcyx/kind`, recommended

- Repo: https://github.com/tehcyx/terraform-provider-kind (Apache-2.0, about 118 stars).
- Releases (GitHub releases API): v0.13.0 (2026-10-22), v0.11.0 (2026-02-05), v0.10.0 (2025-11-23), v0.9.0 (2025-05-21), v0.8.0 (2025-02-15). Roughly 2 to 4 releases a year. There is no v0.12.0 GitHub release; the version jumped from 0.11 to 0.13. 22 commits in the last 12 months, many from Dependabot.
- Currently vendors `sigs.k8s.io/kind v0.33.0` (go.mod on the default branch), which is the latest kind release. It tracks upstream kind closely.
- Open issues: 1 (only a CI-commenter issue), so it is a quiet, low-noise project.
- **Bus factor is about 1.** The maintainer `tehcyx` has 74 commits. The next human contributor has 2. This is the main maturity risk. It is acceptable for a showcase because kind is local-only and the cluster layer sits behind a module interface (§4).
- Resources ([docs/resources/cluster.md](https://github.com/tehcyx/terraform-provider-kind/blob/master/docs/resources/cluster.md)):
  - `kind_cluster` has `name`, `node_image`, `wait_for_ready`, `kind_config` (nodes, `extra_port_mappings`, `kubeadm_config_patches`, `containerd_config_patches`) and `kubeconfig_path`. It exports `kubeconfig`, `context_name`, `endpoint`, `client_certificate`, `client_key` and `cluster_ca_certificate`. Those four connection attributes are exactly what the helm/kubernetes providers need.
  - The doc states: "It does NOT support modification to an existing kind cluster". Every config change is a destroy and recreate, which is fine for kind.
  - **New in v0.13.0: `kind_load`** ([docs/resources/load.md](https://github.com/tehcyx/terraform-provider-kind/blob/master/docs/resources/load.md), PR #98). It is the Terraform equivalent of `kind load docker-image` and pushes a local image onto all nodes. It is useful for loading locally built Mock Agent images, but it couples image builds to Terraform. Treat it as optional (see Open questions).
- Note: the exported `client_key` lands in Terraform state. That is harmless for local kind, but it is one more reason not to ship kind state to a shared backend.

### Alternatives considered

- `kyma-incubator/terraform-provider-kind`: **archived**. The last release was v0.0.11 (2021-11-09). https://github.com/kyma-incubator/terraform-provider-kind
- `null_resource` / `terraform_data` with `local-exec kind create cluster`: this works with no third-party provider, but you lose typed outputs (endpoint, certs), and destroy needs a matching `when = destroy` provisioner. It is only a fallback if `tehcyx/kind` goes stale.

## 2. Bootstrapping Argo CD pointed at this repo

### The constraint that drives everything: provider config from a resource created in the same apply

The kubernetes provider docs warn that passing a cluster resource's credentials into the provider in the same module "will lead to intermittent and unpredictable errors". They say "the most reliable way … is to ensure that the cluster itself and the Kubernetes provider resources can be managed with separate `apply` operations" ([terraform-provider-kubernetes docs/index.md, "Stacking with managed Kubernetes cluster resources"](https://github.com/hashicorp/terraform-provider-kubernetes/blob/main/docs/index.md)).

On top of that, `kubernetes_manifest` "requires API access during planning time … [the cluster] cannot be created in the same apply operation" ([docs/resources/manifest.md](https://github.com/hashicorp/terraform-provider-kubernetes/blob/main/docs/resources/manifest.md)). A root `Application` is a CR, so creating it with `kubernetes_manifest` in the same apply as the cluster **will fail on a fresh `terraform apply`**.

`helm_release` does not need the API during plan. In practice the common kind + helm single-apply pattern works when the provider is configured from `kind_cluster` attributes. It is still exposed to the same caveat, though. The safest design is **two root modules (stacks)**, `cluster` and `bootstrap`, applied in sequence, with outputs handed across (see §4). One root module with helm-only resources is a viable simpler starting point. Note this as a known risk and split only if it bites. (Uncertainty: the "works in practice" claim comes from common usage, not from a HashiCorp guarantee.)

### Option A: `hashicorp/helm`, recommended

- Repo: https://github.com/hashicorp/terraform-provider-helm (MPL-2.0, about 1.08k stars, official HashiCorp provider).
- Releases: v3.3.0 (2026-09-02), v3.2.0 (2026-06-04), v3.1.2 (2026-05-21), v3.1.1 (2025-11-17), v3.1.0 (2025-10-28). That is roughly quarterly. v3.3.0 bundles Helm 3.20.2 and client-go 0.35.1.
- 204 open issues, which is normal for a provider this widely used.
- **v3 breaking syntax** ([v3 upgrade guide](https://github.com/hashicorp/terraform-provider-helm/blob/main/docs/guides/v3-upgrade-guide.md)): v3 moved to the Plugin Framework. `kubernetes { … }` is now `kubernetes = { … }`, and `set { … }` blocks are now `set = [ { … } ]` lists. Most blog posts and examples online still show v2 syntax, so write against v3 from the start.
- Charts: `argo-cd` from https://github.com/argoproj/argo-helm (argo-cd-10.17.2, released 2026-11-11, several releases a week), plus the **`argocd-apps`** chart (argocd-apps-2.0.8, 2026-11-09). `argocd-apps` renders `Application` / `ApplicationSet` / `AppProject` objects from values ([values.yaml](https://github.com/argoproj/argo-helm/blob/main/charts/argocd-apps/values.yaml)). The CR ends up inside a helm release, so it needs no plan-time CRD lookup. Install it with `depends_on = [helm_release.argocd]`.
- Argo CD itself is at v3.6.1 (latest GitHub release).

Sketch:

```hcl
provider "helm" {
  kubernetes = {
    host                   = module.cluster.endpoint
    client_certificate     = module.cluster.client_certificate
    client_key             = module.cluster.client_key
    cluster_ca_certificate = module.cluster.cluster_ca_certificate
  }
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.17.2"   # pin
  namespace        = "argocd"
  create_namespace = true
  wait             = true
}

resource "helm_release" "root_app" {
  name       = "root"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argocd-apps"
  version    = "2.0.8"
  namespace  = "argocd"
  values = [yamlencode({
    applications = {
      root = {
        project = "default"
        source = { repoURL = var.repo_url, targetRevision = var.target_revision, path = "gitops/apps" }
        destination = { server = "https://kubernetes.default.svc", namespace = "argocd" }
        syncPolicy = { automated = { prune = true, selfHeal = true } }
      }
    }
  })]
  depends_on = [helm_release.argocd]
}
```

`target_revision` as a variable lets CI point the root app at the PR branch. That matters because Argo CD pulls from Git, not from the runner's checkout (see Open questions).

### Option B: `argoproj-labs/argocd`, not for bootstrap

- Repo: https://github.com/argoproj-labs/terraform-provider-argocd (MPL-2.0, about 509 stars, under the argoproj-labs org; moved from `oboukili/argocd`).
- Very active: v7.18.0 (2026-11-06), v7.17.2 (2026-10-15), v7.17.1 (2026-10-05), v7.17.0 (2026-09-05), v7.16.0 (2026-08-01). 34 open issues. It tests against Argo CD v3.3 to v3.5 (README compatibility table).
- But the README is explicit: "**The provider is not concerned with the installation/configuration of ArgoCD itself.** … you will need to have an existing ArgoCD deployment and, the ArgoCD API server must be accessible from where you are running Terraform." It talks to the Argo CD API. Inside kind you would need `port_forward_with_namespace` or `core` mode ([docs/index.md](https://github.com/argoproj-labs/terraform-provider-argocd/blob/main/docs/index.md)), which adds moving parts to every apply.
- Its stated purpose is things Kubernetes manifests can't express well, such as project-role JWTs (`argocd_project_token`, `argocd_account_token`). We have no such need. Managing Applications here would also pull in-cluster config back into Terraform and contradict the standing decision.

### Option C: kubectl-style manifest providers, not needed

- `alekc/kubectl` (fork of gavinbunney): https://github.com/alekc/terraform-provider-kubectl. Healthy: v3.0.1 (2026-11-04), v3.0.0 (2026-10-30), 7 open issues. Its `kubectl_manifest` defers API lookups to apply, so it avoids the plan-time CRD problem, and it could apply the upstream `install.yaml` plus a root Application. It is a valid alternative if we ever want raw manifests over Helm, but the helm + `argocd-apps` approach does the same job with one official provider.
- `gavinbunney/kubectl`: https://github.com/gavinbunney/terraform-provider-kubectl. The last release was v1.19.0 (2025-01-10), the last push was 2025-04, and there are 85 open issues. **Avoid**, because it is effectively unmaintained.
- `hashicorp/kubernetes` `kubernetes_manifest`: official and active (v3.5.0, 2026-11-05), but it has the plan-time API requirement described above. It is fine in a separate, later apply. It is not suitable for the first apply.

### Argo CD side: app-of-apps / self-management

- Argo CD's [Cluster Bootstrapping](https://argo-cd.readthedocs.io/en/stable/operator-manual/cluster-bootstrapping/) guide ([source](https://github.com/argoproj/argo-cd/blob/master/docs/operator-manual/cluster-bootstrapping.md)) documents the **App of Apps** pattern: one root Application whose path contains other Application manifests. It recommends ApplicationSets for multi-cluster fan-out. For a single cluster, app-of-apps is the simpler fit, and ApplicationSets can come later for kind and cloud side by side.
- [Declarative Setup → "Manage Argo CD Using Argo CD"](https://argo-cd.readthedocs.io/en/stable/operator-manual/declarative-setup/#manage-argo-cd-using-argo-cd): Argo CD can manage itself. That gives a clean hand-off: Terraform installs a pinned `argo-cd` chart once, and a child Application in `gitops/` can then take over Argo CD's own upgrades. If we do that, set `lifecycle { ignore_changes = all }` (or stop managing the release) on the Terraform side to avoid a tug-of-war. That is a design choice for the implementation ticket.

## 3. State: local vs CI vs cloud

- **Local runs (kind on macOS):** the default `local` backend, with `terraform.tfstate` gitignored. The state describes a cluster that only exists in local Docker, so sharing it is meaningless. It also contains the kind client key.
- **CI (GitHub Actions + kind):** also `local`. The kind cluster lives and dies on the runner, so state should too. Run `apply` → tests → `destroy` (or just let the runner die). No secrets or backend are needed, which also makes fork PRs work.
- **Cloud cluster (later):** a real remote backend, because the cluster outlives the run and needs locking:
  - S3 with `use_lockfile = true`. Terraform 1.11 release notes: "S3 native state locking is now generally available … we've deprecated the DynamoDB-related arguments" ([v1.11.0](https://github.com/hashicorp/terraform/releases/tag/v1.11.0)). OpenTofu shipped the same in 1.10 ("Native S3 Locking", [v1.10.0](https://github.com/opentofu/opentofu/releases/tag/v1.10.0)).
  - Equivalents are `gcs` or `azurerm`, both of which lock natively, chosen by whichever cloud the cluster target picks. CI authenticates via GitHub OIDC rather than static keys.
- **How to make both coexist:** use one root module per environment (`envs/kind`, `envs/<cloud>`), each with its own `backend` block. Avoid one root module with `-backend-config` switching, because backend blocks can't use variables, and partial config gets confusing when one environment is `local`. Terraform workspaces don't fit either, since they share a backend type.

## 4. Letting a cloud cluster module replace kind behind the same interface

Define a **cluster module contract** that every cluster implementation satisfies, and keep Argo CD bootstrap in a separate, cluster-agnostic module:

```
modules/
  cluster-kind/      # tehcyx/kind
  cluster-<cloud>/   # eks/gke/aks later
  argocd-bootstrap/  # helm: argo-cd + argocd-apps root app; knows nothing about kind
envs/
  kind/    main.tf -> cluster-kind + argocd-bootstrap; backend "local"
  <cloud>/ main.tf -> cluster-<cloud> + argocd-bootstrap; backend "s3"/"gcs"/...
```

Contract (outputs every `cluster-*` module must expose):

- `endpoint`, `cluster_ca_certificate`, and either `client_certificate` + `client_key` (kind) or a token / exec-auth config (cloud). A single object output, `kubernetes = { host, cluster_ca_certificate, client_certificate?, client_key?, token?, exec? }`, can feed `provider "helm" { kubernetes = module.cluster.kubernetes }` directly. Cloud clusters normally use short-lived `exec`-based auth, so the contract has to allow it.
- `name` / `context_name` for humans and scripts.
- Optional capability flags, e.g. `supports_image_load` (kind only).

The `argocd-bootstrap` module takes the `kubernetes` object plus `repo_url`, `target_revision`, `path` and chart versions. That keeps it identical across environments, and the Argo CD side (app-of-apps, later ApplicationSets keyed on cluster labels) is unchanged.

Because providers can't be configured inside reusable child modules that are used with `count` / `for_each`, configure the `helm` provider **in the env root module** and pass it the cluster module's outputs. This is standard Terraform module guidance, and it is also where a split into two applies (cluster, then bootstrap) can happen if the single-apply caveat in §2 bites.

## 5. OpenTofu vs Terraform

- Latest releases: Terraform v1.17.2 (2026-11-11), OpenTofu v1.13.9 (2026-11-05).
- **Provider availability:** all of the picks are in the OpenTofu registry at the same current versions as GitHub. I checked [opentofu/registry](https://github.com/opentofu/registry) `providers/*.json`: `tehcyx/kind` 0.13.0, `hashicorp/helm` 3.3.0, `hashicorp/kubernetes` 3.5.0, `argoproj-labs/argocd` 7.18.0 and `alekc/kubectl` 3.0.1. Nothing here forces either tool.
- **Differences that could matter later, none of them blocking:**
  - OpenTofu has client-side **state encryption** (since 1.7, [v1.7.0 notes](https://github.com/opentofu/opentofu/releases/tag/v1.7.0)), which is attractive for remote cloud state that holds cluster credentials. Terraform has no equivalent and relies on backend-side encryption.
  - Terraform 1.10+ has **ephemeral resources/values** ([v1.10.0 notes](https://github.com/hashicorp/terraform/releases/tag/v1.10.0)), which can keep credentials out of state. OpenTofu has been adding its own ephemeral support, but I did not verify parity for this note.
  - OpenTofu 1.10 adds OCI registry distribution for providers and modules. It's irrelevant here.
- **Recommendation:** pick one CLI for CI (e.g. `hashicorp/setup-terraform` or `opentofu/setup-opentofu`). Keep the configuration to the common subset (no OpenTofu-only encryption blocks, no Terraform-only ephemeral resources) unless a later ticket decides otherwise. Licensing (BSL vs MPL) is the only reason to prefer OpenTofu for a public showcase, and it's a values call, not a technical one.

## Open questions / fog

1. **Single apply vs two stacks.** Start with one root per env (kind cluster + helm bootstrap in one apply)? Or split `cluster` and `bootstrap` from day one, following HashiCorp's guidance? I lean toward starting single and splitting if flaky, but this needs a decision.
2. **Who builds and loads Mock Agent images into kind.** Use `kind_load` in Terraform, or a `kind load docker-image` step in a Makefile/CI? The second keeps Terraform out of the inner dev loop.
3. **Argo CD tracking a PR branch in CI.** The root app's `targetRevision` must be the PR's branch/SHA, and the repo is public, so no repo credentials are needed. For fork PRs, the source repo differs as well.
4. **Argo CD self-management hand-off.** Does Terraform keep owning the `argo-cd` helm release, or does a `gitops/` Application adopt it after bootstrap?
5. **Cloud target and backend.** These are unknown until the cloud cluster ticket. The contract in §4 is designed so that choice only adds a `cluster-<cloud>` module and an `envs/<cloud>` root.
6. **Registry pages not directly fetched.** registry.terraform.io and registry.opentofu.org were blocked from this sandbox. Release and version data came from the provider GitHub repos (the source the Registry publishes from) and the opentofu/registry index repo. Registry download counts were not collected.
