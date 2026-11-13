# agent-swarm

Kernel-level observation and **Guardrails** for AI agent swarms on Kubernetes, using [Tetragon](https://tetragon.io).

The Agents are **Mock Agents** — bash workloads that play scripted benign and rogue **Scenarios** — so no LLM tokens are spent. A real Agent can take a Mock Agent's place without any other change ([how](docs/real-agents.md)).

> **Status:** walking skeleton complete. One command builds a local cluster where a benign Scenario shows up on a dashboard and a rogue one is stopped by a Guardrail, and CI proves it on every PR and nightly against the latest Tetragon. The planning record is the closed [project map](https://github.com/henry-ward-gh/agent-swarm/issues/1).

## What's in the box

- **A Swarm** — one Orchestrator handing Tasks to Workers through a per-Swarm Valkey broker, in its own namespace ([`agents/`](agents/)).
- **Guardrails** — three Tetragon kprobe policies that kill an Agent's action in the kernel: egress to anything but an Approved Destination, reading the ServiceAccount token, and executing a program from the Workspace ([`policies/`](policies/)).
- **Scenarios** — two benign and three rogue, each rogue one tripping a different Guardrail ([`agents/mock/`](agents/mock/)).
- **Observability** — Prometheus, Loki, Alloy and Grafana with a **Swarm activity** dashboard: Task outcomes, Guardrail kills by policy, the kill events themselves, and exec rates per Agent pod ([`gitops/platform/observability/`](gitops/platform/observability/)).
- **CI** — lint, Trivy, `terraform plan`, a signed image on GHCR, and an e2e job that brings the whole platform up on kind and judges every Task ([`tests/`](tests/)).

Want a real AI Agent in the slot instead of the Mock? See [Swapping in a real Agent](docs/real-agents.md).

## Where things live

| Path | What |
|---|---|
| [`terraform/`](terraform/) | Cluster + Argo CD bootstrap |
| [`gitops/`](gitops/) | Everything in-cluster, deployed by Argo CD |
| [`agents/`](agents/) | Agent & Swarm charts, Mock Agent image, Scenarios, Goals |
| [`policies/`](policies/) | Tetragon Guardrail templates |
| [`protocol/`](protocol/) | Goal / Task / Result JSON Schemas |
| [`tests/`](tests/) | End-to-end Guardrail tests |
| [`CONTEXT.md`](CONTEXT.md) | Domain vocabulary |
| [`docs/adr/`](docs/adr/) | Architecture decisions |
| [`docs/real-agents.md`](docs/real-agents.md) | Swapping a real AI Agent into the Agent slot |

## Quickstart (macOS)

Install the tools. Homebrew's formula for [Task](https://taskfile.dev) is `go-task`, and the binary it installs is `task`:

```sh
brew install go-task colima docker kind kubectl helm jq
brew install hashicorp/tap/terraform
```

Start a VM with room for the platform, then bring everything up:

```sh
colima start --cpu 4 --memory 8   # ran the whole platform healthily on Apple Silicon (not tuned, so less may do)
task up                           # kind cluster + Argo CD following main; a few minutes
kubectl -n argocd get applications   # wait until every app is Synced and Healthy
```

Give the Swarm some work and watch it:

```sh
task goal -- smoke --wait 60          # benign: both Tasks succeed
task goal -- rogue-exfil --wait 60    # rogue: the Task fails with exit 137, killed by guardrail-egress
task grafana:ui                       # http://localhost:3000, admin / admin → Dashboards → Swarm activity
```

The dashboard lists Tasks by **Scenario**, not by Goal. `smoke` shows up as `benign-build` and `benign-fetch`, each `started` then `succeeded`. The plans live in [`agents/mock/goals/`](agents/mock/goals/).

Clean up with `task down` and `colima stop`.

## Development

Requires [Task](https://taskfile.dev) and [pre-commit](https://pre-commit.com). The tests need [bats](https://github.com/bats-core/bats-core).

```sh
task                     # list every task
task setup               # install git hooks
task lint                # run all linters, as CI does
task up                  # kind cluster + Argo CD following main (task down to remove)
task up TARGET_REVISION=my-branch   # follow a pushed branch instead
task argocd:ui           # Argo CD UI on localhost:8080
task grafana:ui          # Grafana (Swarm activity dashboard) on localhost:3000, admin / admin
task images:load         # build the Mock Agent image and load it into kind
task goal -- smoke --wait 60   # submit a Goal to the demo Swarm
task test:unit           # harness unit tests, no cluster
task test:e2e            # Guardrail + observability e2e against the cluster from task up
```

See [`agents/`](agents/) to run a Swarm, and [`tests/`](tests/) for how a rogue Task is judged **Blocked**.

Locally the cluster runs on [Colima](https://github.com/abiosoft/colima) (Docker Desktop and OrbStack are untested for Tetragon enforcement). The Guardrails are kprobe-based because neither Colima's kernel nor GitHub's runners enable BPF LSM ([ADR 0003](docs/adr/0003-kprobe-guardrails-with-pinned-ip-allowlist.md)).

Commits follow [Conventional Commits](https://www.conventionalcommits.org).

### Merging to `main`

`main` is protected by the `protect-main` ruleset: changes land through a pull request, the `pre-commit` (workflow `lint`) and `e2e` checks must pass, and force-pushes and deletion are blocked. No approving review is required (the repo has one maintainer). A docs-only PR (`docs/`, `*.md`, `LICENSE`) still gets a passing `e2e`, because that job skips its cluster steps rather than not running.

The same ruleset asks GitHub Copilot to review every non-draft PR, and again on each push. Its suggestions are applied by hand (GitHub has no setting to auto-commit them).

## Licence

[MIT](LICENSE)
