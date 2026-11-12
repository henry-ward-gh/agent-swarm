# agents

The Agent slot ([ADR 0001](../docs/adr/0001-scenarios-arrive-as-tasks.md), [ADR 0002](../docs/adr/0002-valkey-broker-between-agents.md)).

| Path | What |
|---|---|
| [`charts/agent/`](charts/agent/) | One role (Orchestrator or Workers) of a Swarm: hardened Deployment (read-only root, writable `/workspace`, non-root, no capabilities), zero-RBAC ServiceAccount with its token mounted, broker password from a Secret. Swap `image` to put a real Agent (via an Adapter) in the slot. |
| [`charts/swarm/`](charts/swarm/) | A Swarm in its own namespace: the Valkey broker + the Agent chart twice (`orchestrator`, `worker`). |
| [`mock/`](mock/) | The Mock Agent image: bash runtime, Scenarios, Goal plans. |

Labels every Agent carries: `agent-swarm.io/swarm`, `agent-swarm.io/role` (`orchestrator`/`worker`), `agent-swarm.io/implementation` (dashboards only — Guardrails never select on it). The broker carries `agent-swarm.io/component: broker` and no role.

## Try it on a kind cluster

```sh
task images:load                      # build agent-swarm/mock-agent:dev and load it into kind
helm dependency build agents/charts/swarm
helm install demo agents/charts/swarm -n swarm-demo --create-namespace --set broker.password=dev-only
task goal -- smoke --wait 60          # prints the Goal id, then the Results
```

Without `broker.password` the chart commits an annotated Secret for the in-cluster secret-generator to fill ([ADR 0004](../docs/adr/0004-two-stage-terraform-secrets-generated-in-cluster.md)).

## Guardrails

Set `guardrails.enabled=true` (needs Tetragon and a pinned `broker.clusterIP`) and the Swarm chart renders the three Guardrails from [`policies/`](../policies/). The demo Swarm Application in `gitops/root` does this; `task up` then deploys Outside World, so `smoke` succeeds and each rogue Goal (`rogue-exfil`, `rogue-token-theft`, `rogue-dropped-binary`) fails with exit 137. `task test:e2e` checks that on a live cluster ([`tests/`](../tests/)).

## Published image

Every push to `main` publishes the Mock Agent to `ghcr.io/henry-ward-gh/agent-swarm/mock-agent`, tagged with the commit SHA (and `main` / `latest` when that commit is the head of `main`), after a Trivy scan (HIGH/CRITICAL with a fix fail the build — the same scan runs on every PR). Each image is signed by digest with keyless [cosign](https://docs.sigstore.dev); verify one with:

```sh
cosign verify ghcr.io/henry-ward-gh/agent-swarm/mock-agent:<sha> \
  --certificate-identity 'https://github.com/henry-ward-gh/agent-swarm/.github/workflows/agents.yml@refs/heads/main' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

Retention: the newest 60 package versions are kept (about 30 images, since each signature is a version too) and a version tagged `main` or `latest` is never pruned ([`scripts/ghcr-prune.sh`](../scripts/ghcr-prune.sh), run after each publish). CI and local runs don't pull from GHCR: they build a SHA-tagged image and `kind load` it.
