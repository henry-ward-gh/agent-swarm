# protocol

How Agents in a Swarm talk to each other through the Swarm's Valkey broker ([ADR 0002](../docs/adr/0002-valkey-broker-between-agents.md)). The JSON Schemas are the contract an Adapter implements. A Mock Agent reads a Goal's `name` and a Task's `scenario`. A real Agent reads `prompt` instead. [Swapping in a real Agent](../docs/real-agents.md) walks through what a Worker and an Orchestrator Adapter must do.

| Message | Schema | Example |
|---|---|---|
| Goal | [`goal.schema.json`](goal.schema.json) | [`examples/goal.smoke.json`](examples/goal.smoke.json) |
| Task | [`task.schema.json`](task.schema.json) | [`examples/task.benign-build.json`](examples/task.benign-build.json) |
| Result | [`result.schema.json`](result.schema.json) | [`examples/result.failed-137.json`](examples/result.failed-137.json) |
| Task event | [`task-event.schema.json`](task-event.schema.json) | [`examples/task-event.failed-137.json`](examples/task-event.failed-137.json) |

## Broker keys

| Key | Type | Written by | Read by | Meaning |
|---|---|---|---|---|
| `goals` | list | submitter (`task goal`) `LPUSH` | Orchestrator `BRPOP` | Goals waiting to be split |
| `tasks` | list | Orchestrator `LPUSH` | Workers `BLMOVE … RIGHT LEFT` | Shared Task queue (FIFO); any free Worker takes the next |
| `running:<worker>` | list | Worker (`BLMOVE` target) | Orchestrator | Task a Worker has claimed and is running |
| `heartbeat:<worker>` | string, 10 s TTL | Worker, every 3 s for its whole life | Orchestrator | Worker is alive |
| `goal:<goalId>:tasks` | list | Orchestrator | anyone | Task ids the Goal was split into, in order |
| `goal:<goalId>:count` | string | Orchestrator, after the last Task is queued | anyone | Number of Tasks the Goal was split into; its presence means the split is complete, so wait for it before reading `goal:<goalId>:tasks` |
| `goal:<goalId>:error` | string | Orchestrator | anyone | Why a Goal could not be split (e.g. unknown plan) |
| `result:<taskId>` | string (Result JSON) | Worker, or Orchestrator for `lost` | harness | Outcome of one Task |
| `results` | list | same | anyone | All Results, newest first |

Delivery is at-most-once. A Task whose Worker's heartbeat expires while it sits in `running:<worker>` is recorded `lost` and never retried.

Every message carries `"version": 1`.

## Task events (logs, not the broker)

Besides Results, every Agent writes one JSON line to **stdout** per Task transition, so the Swarm activity dashboard can show Task flow without a metrics endpoint. The Worker writes `started`, then `succeeded` or `failed`; the Orchestrator writes `lost` (a killed Worker cannot log its own death). Human-readable logs go to stderr, so stdout carries only these lines. An Adapter for a real Agent must emit the same lines (`SWARM_NAME` gives the `swarm` field; `scenario` is `""` for a prompt Task). The collector can't tell stdout from stderr and treats every log line starting with `{` as a Task event, so an Agent must not write other JSON log lines.
