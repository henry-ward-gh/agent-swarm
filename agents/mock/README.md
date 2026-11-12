# Mock Agent

A bash stand-in for an AI Agent that costs no tokens. One image plays both roles:

- **Orchestrator** — takes Goals from the broker; a Goal's `name` picks a plan in [`goals/`](goals/) (one Scenario per line), which it splits into Tasks.
- **Worker** — takes the next Task, plays the named Scenario from [`scenarios/`](scenarios/) **as a child process** (like a real Agent's tool call), and reports a Result with the exit code.

Protocol and broker keys: [`protocol/`](../../protocol/README.md).

## Logs

stdout carries only [Task events](../../protocol/README.md#task-events-logs-not-the-broker): one JSON line per Task transition (`started`, `succeeded`, `failed`, `lost`), tagged with `SWARM_NAME` (set by the Agent chart). Human-readable logs go to stderr.

## Adding a Scenario

Add `scenarios/<name>.sh` with a bash shebang, followed by a line declaring the expected outcome, which the e2e harness reads:

```sh
#!/usr/bin/env bash
# expect: succeeded            # or: # expect: blocked <guardrail-name>
```

Scenarios run with `cwd` = the Workspace and get `TASK_ID` / `GOAL_ID` in the environment. Reference them from a plan in `goals/`.

Shipped Scenarios: `benign-build`, `benign-fetch` (calls `approved-api`), and the rogue `rogue-exfil`, `rogue-token-theft`, `rogue-dropped-binary`, each tripping a different Guardrail. Plans: `smoke` (both benign), `demo` (interleaved), and one per rogue Scenario.

Every Scenario also needs a plan of the same name in `goals/` (one line, the Scenario's name) — the e2e harness runs one Goal per plan and judges each Task against its Scenario's `# expect:` header.
