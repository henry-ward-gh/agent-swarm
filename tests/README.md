# tests

End-to-end Guardrail tests: submit Goals to a Swarm and judge every Task. The harness drives the Mock Agent's named plans, so it tests the `demo` Mock Swarm. A Swarm of [real Agents](../docs/real-agents.md) runs alongside it, untested by this harness.

| Path | What |
|---|---|
| [`e2e/guardrails.bats`](e2e/guardrails.bats) | Live-cluster tests: every Guardrail is loaded on every Tetragon agent, then one test per Goal plan in `agents/mock/goals/`. |
| [`e2e/observability.bats`](e2e/observability.bats) | Runs after the Guardrail tests: Loki holds the Guardrail event, the `failed` (137) and `succeeded` Task events and the exec events for the Swarm, Prometheus is scraping Tetragon, every Loki query in the dashboard is valid LogQL (run against the live Loki), and Grafana loaded the dashboard and can query both datasources (via a port-forward). Polls, because ingest is asynchronous. |
| [`unit/`](unit/) | The verdict logic against fixtures and a fake `kubectl` — no cluster. |
| [`lib/observability.bash`](lib/observability.bash) | Asks Loki and Prometheus through the API server's service proxy, and Grafana through a port-forward (its API needs credentials). |
| [`lib/verdict.bash`](lib/verdict.bash) | The **Blocked** verdict as pure functions (see `CONTEXT.md`). |
| [`lib/cluster.bash`](lib/cluster.bash) | What the harness reads from a cluster: Tetragon events, the Exfil Sink, loaded Guardrails. |
| `lib/junit-summary.py` | JUnit → the Markdown table in the Actions run summary. |

## The verdict

The harness decides, never the Worker. A Task is judged against the `# expect:` header on line 2 of its Scenario:

- `# expect: blocked <guardrail>` — **Blocked** only if the Result is `failed` with `exitCode` 137, **and** that Guardrail's policy fired on the Result's `worker` pod in the Task's namespace inside `[startedAt, finishedAt]` with action `KPROBE_ACTION_SIGKILL` or `KPROBE_ACTION_OVERRIDE`. (A timeout also exits 137; without the event it isn't Blocked.) For `guardrail-egress` the Exfil Sink's `GET /received` must also be empty.
- `# expect: succeeded` — the Result is `succeeded` **and** no Guardrail fired on that Worker in its window.

Each Task is capped at 60 s by the Worker (`TASK_TIMEOUT`, which kills it with 137 — hence the Guardrail-event requirement above); the harness waits up to 150 s per Goal and never retries. Adding a Scenario adds its test: give it the header and a plan of the same name in `agents/mock/goals/`.

## Running

```sh
task test:unit                 # no cluster; needs bats
task up && task test:e2e       # live; JUnit, Results and Tetragon events land in tests/results/
```

CI is [`.github/workflows/e2e.yml`](../.github/workflows/e2e.yml): the `e2e` job runs on PRs, pushes to `main` and nightly. Nightly runs the latest Tetragon chart (a failure means upstream broke us). A docs-only PR skips the cluster steps and still reports `e2e` green. Failures upload Tetragon events, Argo CD status, pod logs and Results as an artifact.
