# protocol

How Agents in a Swarm talk to each other through the Swarm's Valkey broker ([ADR 0002](../docs/adr/0002-valkey-broker-between-agents.md)). The JSON Schemas are the contract an Adapter implements.

| Message | Schema | Example |
|---|---|---|
| Goal | [`goal.schema.json`](goal.schema.json) | [`examples/goal.smoke.json`](examples/goal.smoke.json) |
| Task | [`task.schema.json`](task.schema.json) | [`examples/task.benign-build.json`](examples/task.benign-build.json) |
| Result | [`result.schema.json`](result.schema.json) | [`examples/result.failed-137.json`](examples/result.failed-137.json) |

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
