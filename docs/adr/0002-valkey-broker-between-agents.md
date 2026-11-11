# A Valkey broker sits between Orchestrator and Workers

Tasks travel through a per-Swarm Valkey instance rather than over HTTP between Agents. The Orchestrator pushes Tasks onto a list; Workers block-pop them, report Results, and refresh heartbeats there. We chose a broker over the simpler "Orchestrator serves an HTTP API" because it keeps every occupant of the Agent slot — Orchestrator included — a pure client: no Agent listens on a port, each needs egress to exactly one in-Swarm address, a real Agent's Adapter only has to be a client, and a bash Mock Agent can speak it with `valkey-cli`. Valkey over Redis for its BSD licence.

## Considered options

- **Orchestrator HTTP API, Workers pull** — no extra component, but makes the Orchestrator a server (awkward in bash, forces a real LLM Orchestrator's Adapter to host an API).
- **HTTP push to Workers** — every Worker becomes a server: more attack surface, worse for bash and Adapters.
- **NATS/JetStream** — capable but heavier and less natural from bash.

## Consequences

- Delivery is at-most-once: a Worker claims a Task by moving it to a running list; a Task whose Worker's heartbeat expires is marked lost and never retried, so a rogue Task can't kill Workers in a loop.
- The broker password is a real credential every Agent holds — itself a target for rogue Scenarios.
