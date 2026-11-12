# policies

Tetragon `TracingPolicyNamespaced` templates for the Guardrails ([ADR 0003](../docs/adr/0003-kprobe-guardrails-with-pinned-ip-allowlist.md)), rendered per Swarm by the Swarm chart.

| Template | Hook → action | Posture |
|---|---|---|
| [`guardrail-egress`](templates/guardrail-egress.yaml) | `tcp_connect` to anything but the broker, loopback or a declared Approved Destination → `Sigkill` | allowlist of pinned ClusterIPs |
| [`guardrail-credential-files`](templates/guardrail-credential-files.yaml) | `security_file_open` under the ServiceAccount directory (prefix) → `Override` + `Sigkill` | denylist |
| [`guardrail-workspace-exec`](templates/guardrail-workspace-exec.yaml) | `security_bprm_check` on `/workspace/` → `Override` + `Sigkill` | denylist |

Helm can't read files outside a chart, so `agents/charts/swarm/templates/guardrails` is a symlink to [`templates/`](templates/). The templates use the Swarm chart's helpers and values (`guardrails.*`, `broker.clusterIP`, `worker|orchestrator.egress.allow`). Off by default (`guardrails.enabled`): they need Tetragon's CRDs.

- Guardrails select `agent-swarm.io/swarm=<swarm>` **and** the `agent-swarm.io/role` label, so Orchestrator and Workers are guarded and the broker is not.
- The egress list is IPs only — `tcp_connect` matching can't pair an address with a port — so every Approved Destination needs its own pinned ClusterIP. The render fails if a pinned IP is outside `guardrails.serviceCIDR`, or if the broker isn't pinned.
- Pin IPs from the Service CIDR's static band (`10.96.0.x` on kind) so the API server never hands them out dynamically.
- Policies using `Override` set `disable-kprobe-multi`.
