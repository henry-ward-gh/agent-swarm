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
task setup   # install git hooks
task lint    # run all linters, as CI does
```

Commits follow [Conventional Commits](https://www.conventionalcommits.org).

## Licence

[MIT](LICENSE)
