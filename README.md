# agent-swarm

Kernel-level observation and **Guardrails** for AI agent swarms on Kubernetes, using [Tetragon](https://tetragon.io).

The Agents are **Mock Agents** — bash workloads that play scripted benign and rogue **Scenarios** — so no LLM tokens are spent. A real Agent can take a Mock Agent's place without any other change.

> **Status:** early. Planning and progress are tracked on the [project map](https://github.com/henry-ward-gh/agent-swarm/issues/1).

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

## Development

Requires [Task](https://taskfile.dev) and [pre-commit](https://pre-commit.com).

```sh
task setup               # install git hooks
task lint                # run all linters, as CI does
task up                  # kind cluster + Argo CD following main (task down to remove)
task argocd:ui           # Argo CD UI on localhost:8080
task grafana:ui          # Grafana (Swarm activity dashboard) on localhost:3000, admin / admin
task images:load         # build the Mock Agent image and load it into kind
task goal -- smoke --wait 60   # submit a Goal to the demo Swarm
```

See [`agents/`](agents/) to run a Swarm.

Commits follow [Conventional Commits](https://www.conventionalcommits.org).

### Merging to `main`

`main` is protected by the `protect-main` ruleset: changes land through a pull request, the `pre-commit` (workflow `lint`) and `e2e` checks must pass, and force-pushes and deletion are blocked. No approving review is required (the repo has one maintainer). A docs-only PR (`docs/`, `*.md`, `LICENSE`) still gets a passing `e2e`, because that job skips its cluster steps rather than not running.

The same ruleset asks GitHub Copilot to review every non-draft PR, and again on each push. Its suggestions are applied by hand (GitHub has no setting to auto-commit them).

## Licence

[MIT](LICENSE)
