# Swapping in a real Agent

The Mock Agent holds the Agent slot so nothing here spends LLM tokens. A real Agent (Claude Code, an SDK-built agent, anything that runs tools) can take its place without changing the Swarm chart, the broker or the Guardrails. Only the image changes, plus the values that describe what the new Agent needs ([ADR 0001](adr/0001-scenarios-arrive-as-tasks.md)).

Most real Agents don't speak the broker protocol, so they come wrapped in an **Adapter**. The Adapter is a thin program in the same image that takes Tasks from the broker, hands each one to the Agent as a prompt, and writes the Result back. This guide is the contract that Adapter has to meet.

## 1. What the slot requires

The Agent chart (`agents/charts/agent`) runs every occupant the same way:

| Requirement | Why |
|---|---|
| An executable called `agent` on `PATH`, with `agent run` (the main loop) and `agent ready` (exit 0 when the broker answers) | The chart starts the container with `args: ["run"]` and uses `agent ready` as the readiness probe. The chart sets only `args`, so the image's `ENTRYPOINT` must be `agent` (a wrapper script is fine), and it must also be on `PATH` for the probe. |
| Runs as UID/GID 10001, with no capabilities and no privilege escalation | Pod `securityContext` |
| A read-only root filesystem, where `/workspace` is the only writable path (an `emptyDir`, 256 Mi by default) | The **Workspace**. Set `HOME` and `TMPDIR` under `/workspace` (with `env`), because most Agent CLIs write config and caches to `$HOME`. Nothing under `/workspace` may be *executed*, though (`guardrail-workspace-exec`), so bake every binary the Agent runs into the image: its CLI, MCP servers, language runtimes, `node_modules/.bin`. Anything an Agent installs into `$HOME` at runtime and then runs is killed. |
| A mounted ServiceAccount token with zero RBAC | The token is bait. Reading it is what `rogue-token-theft` does, and the `guardrail-credential-files` Guardrail kills it. |
| Task events are the only log lines that start with `{`. Send them to stdout and send human logs to stderr. | Alloy can't tell stdout from stderr. It ships every container log line that starts with `{` to Loki as a Task event, so an Agent that writes JSON logs would pollute the dashboard. Turn JSON logging off, or prefix those lines. |

The chart provides this environment:

| Variable | Value |
|---|---|
| `AGENT_ROLE` | `orchestrator` or `worker` |
| `SWARM_NAME` | The Swarm's name |
| `POD_NAME` | The pod's name. A Worker uses it as its broker identity. |
| `VALKEY_HOST`, `VALKEY_PORT` | The Swarm's broker (`<swarm>-valkey:6379`) |
| `REDISCLI_AUTH` | The broker password, taken from the `<swarm>-broker` Secret |
| `WORKSPACE` | `/workspace` |
| `TASK_TIMEOUT` | Seconds a Task may run. Kill the Agent's work after this long and report exit 137. |

Anything else, such as an API key or `HOME`, goes in the role's `env` list.

## 2. What the Adapter does

The full key table and the JSON Schemas are in [`protocol/`](../protocol/README.md). Every message carries `"version": 1`.

**A Worker Adapter:**

1. Writes its first heartbeat (`SET heartbeat:$POD_NAME 1 EX 10`) before claiming anything, then refreshes it every 3 s for its whole life. The Orchestrator records a claimed Task whose Worker has no heartbeat as `lost`.
2. Claims a Task with `BLMOVE tasks running:$POD_NAME RIGHT LEFT <timeout>`.
3. Reads the Task's `prompt`, plus `inputs` if set, and runs the Agent on it with `/workspace` as the working directory.
4. Writes a Result (`SET result:<taskId>` and `LPUSH results`) with `status` set to `succeeded` or `failed` and an `exitCode`, plus the other fields [`result.schema.json`](../protocol/result.schema.json) requires. Then it runs `DEL running:$POD_NAME`.
5. Writes Task events to stdout: `started` when it claims the Task, then `succeeded` or `failed` with the exit code. Each is one JSON line, and no other log line may start with `{` (schema: [`task-event.schema.json`](../protocol/task-event.schema.json)). For a prompt Task, set `scenario` to `""`.

Run the Agent's tool calls as **child processes** of the Adapter, which most Agents already do. A Guardrail `Sigkill` then kills only the offending tool (exit 137), and the Worker survives to report the Task as `failed`. Anything that runs *inside* the Agent's own process counts as the Agent, not a tool. Examples are a built-in web fetch, or an SDK agent calling its model. So if that is killed, the whole Worker dies and the Task ends `lost`. The same happens if the Adapter and the Agent are one process.

**An Orchestrator Adapter:**

1. Takes Goals with `BRPOP goals`, and reads the Goal's `prompt`. The Mock Orchestrator reads `name` instead.
2. Splits the Goal into Tasks, each with a `prompt`. For each Task it runs `RPUSH goal:<goalId>:tasks <taskId>` and then `LPUSH tasks <task>`. When all Tasks are queued, it runs `SET goal:<goalId>:count <n>`. Waiters read the list only once the count exists, so it must be written last. If it can't split a Goal, it runs `SET goal:<goalId>:error <why>`.
3. Reaps lost Tasks. Each `running:<worker>` key whose heartbeat has expired becomes a `lost` Result with a null `exitCode`, plus a `lost` Task event. It is never retried.

The Mock Agent ([`agents/mock/bin/agent`](../agents/mock/bin/agent)) does all of this in about 200 lines of bash, so it doubles as a reference implementation.

The two roles are separate charts, so you can swap one role without the other. For example, a real Orchestrator can plan, while real Workers act. A mixed Swarm only works if the Workers understand the Tasks the Orchestrator sends. The Mock Orchestrator sends `scenario` Tasks, never `prompt` Tasks.

## 3. Reaching a real model API

The `guardrail-egress` Guardrail kills any TCP connection that isn't to the Swarm's broker, `127.0.0.1` (IPv6 `::1` is not allowed), or a declared **Approved Destination**. It matches pinned ClusterIPs only, so you can't allowlist a hostname such as `api.anthropic.com`, and its public IPs aren't stable ([ADR 0003](adr/0003-kprobe-guardrails-with-pinned-ip-allowlist.md)). DNS uses UDP and isn't affected.

The supported route is an in-cluster gateway:

1. Run an LLM gateway or forward proxy as a Service with a pinned ClusterIP. Take the IP from the static band, `10.96.0.x` on kind. Put it in its own namespace, outside the Swarm. Swarm Guardrails only select pods that carry a Swarm role label, so the gateway is free to reach the internet.
2. Add `<ip>:<port>` to `worker.egress.allow`, or to `orchestrator.egress.allow`. The Swarm has one egress Guardrail, and its allowlist is the union of both roles' entries plus the broker, so either role's entry covers both. Declare it on the role that actually needs it, so the values say why it's there.
3. Point the Agent at the gateway, for example with `ANTHROPIC_BASE_URL=http://<gateway-svc>.<ns>.svc.cluster.local:<port>`.

`approved-api` in [`gitops/platform/outside-world/`](../gitops/platform/outside-world/) is a stand-in for exactly this gateway. Reuse its pattern: one pinned IP per Approved Destination, and never two services on one IP.

**Keep the API key in the gateway, not the Agent.** A rogue Task can read whatever the Agent can read. With the key in the gateway, an exfiltration has nothing worth stealing. If the Agent must hold the key, create the Secret out of band and reference it from `env`. Never commit it. The in-cluster secret-generator ([ADR 0004](adr/0004-two-stage-terraform-secrets-generated-in-cluster.md)) only makes random passwords.

```sh
kubectl -n swarm-<name> create secret generic llm-api --from-literal=key=…
```

## 4. Deploying it

Build and load the image just as the Mock Agent's is (`kind load docker-image …`), or push it to a registry the cluster can pull from. Then override the role values. With Helm directly:

```yaml
# real-swarm.yaml
global:
  swarm: real
broker:
  clusterIP: 10.96.0.130          # pinned, so the egress Guardrail can allow it
guardrails:
  enabled: true
worker:
  replicas: 2
  implementation: claude-code       # a dashboard label only; Guardrails never select on it
  image:
    repository: ghcr.io/you/claude-code-adapter
    tag: "1.0.0"
  egress:
    allow:
      - 10.96.0.140:8080            # your in-cluster LLM gateway
  taskTimeoutSeconds: 600
  resources:
    limits: { cpu: "1", memory: 1Gi }
  workspace:
    sizeLimit: 2Gi
  env:
    - { name: HOME, value: /workspace/.home }
    - { name: TMPDIR, value: /workspace/.tmp }
    - { name: ANTHROPIC_BASE_URL, value: http://llm-gateway.llm-gateway.svc.cluster.local:8080 }
orchestrator:
  implementation: claude-code
  image:
    repository: ghcr.io/you/claude-code-adapter
    tag: "1.0.0"
  env:
    - { name: HOME, value: /workspace/.home }
    - { name: ANTHROPIC_BASE_URL, value: http://llm-gateway.llm-gateway.svc.cluster.local:8080 }
```

```sh
helm dependency build agents/charts/swarm
helm install real agents/charts/swarm -n swarm-real --create-namespace -f real-swarm.yaml
```

To have Argo CD own it instead, add an entry to the `platform:` map in [`gitops/root/values.yaml`](../gitops/root/values.yaml) modelled on `demo`. Use the same values, set `namespace: swarm-real` and `serverSideDiff: true`, and keep the `ignoreDifferences` for the `<swarm>-broker` Secret. Leave `followImageTag` unset, because it sets `global.image.tag` to the Mock Agent's build. A per-role `image.tag` would override it anyway.

The per-role `image` takes precedence over `global.image`. Each Swarm lives in its own namespace and needs its own pinned broker IP.

## 5. Submitting a Goal

`task goal` sends Mock plan names (`{"name": …}`). A real Orchestrator wants a `prompt`, so push the Goal yourself:

```sh
goal=$(jq -cn --arg id "$(uuidgen | tr A-Z a-z)" --arg p "Add a /healthz endpoint to the service in /workspace/app" \
  '{version: 1, id: $id, prompt: $p}')
kubectl -n swarm-real exec -i deploy/real-valkey -c valkey -- valkey-cli --no-auth-warning LPUSH goals "$goal"
```

Results land in `result:<taskId>`, and the Swarm activity dashboard shows the Tasks once the Adapter writes Task events. Pick the Swarm in the `swarm` dropdown.

## 6. What changes, and what doesn't

| Piece | With a real Agent |
|---|---|
| Guardrails | They apply unchanged, because they select on the `swarm` and `role` labels and never on `implementation`. Expect them to bite legitimate work. `guardrail-workspace-exec` kills any program executed from `/workspace` (`./build/app` is killed, `bash script.sh` is not, and so is anything installed under a `/workspace` `$HOME`), and `guardrail-egress` kills package installs and git clones that don't go through an Approved Destination. That's the point, but plan the Agent's work around it, or add Approved Destinations for mirrors. |
| Swarm activity dashboard | It works if the Adapter writes Task events. Guardrail events, kills and exec rates need nothing from the Agent, because they come from Tetragon. |
| Results and the **Blocked** verdict | Results are the same. The verdict is still the harness's job, never the Worker's. |
| e2e harness (`task test:e2e`) | **Mock only.** It submits named plans and judges each Task against its Scenario's `# expect:` header. Keep the `demo` Mock Swarm for CI, and run real Swarms alongside it. |
| Cost | Real tokens. Each Worker replica takes Tasks in parallel. |

## Checklist

- [ ] The image provides `agent run` and `agent ready`, runs as UID 10001, and writes only under `/workspace`.
- [ ] The Worker heartbeats before claiming, claims with `BLMOVE`, writes a Result, and clears `running:$POD_NAME`.
- [ ] The Orchestrator writes `goal:<id>:count` last and reaps lost Tasks.
- [ ] Tool calls run as child processes, and every binary the Agent executes is in the image, not under `/workspace`.
- [ ] Task events are the only log lines that start with `{`, and they go to stdout.
- [ ] The model API is reached through a gateway with a pinned ClusterIP, which is on the role's `egress.allow`.
- [ ] No API key is committed, and preferably none is held by the Agent.
- [ ] The Swarm has its own namespace and pinned broker IP, with `guardrails.enabled: true`.
