#!/usr/bin/env bats
# The Swarm activity pipeline on a live cluster (task up first). Runs after guardrails.bats (alphabetical),
# so every rogue Goal has already been played: Tetragon's events and the Agents' Task events must have
# reached Loki, and Prometheus must be scraping Tetragon. Ingest is asynchronous, hence `eventually`.

setup() {
  load ../lib/observability
  SWARM="${SWARM_NAMESPACE:-swarm-demo}"
  SWARM="${SWARM#swarm-}"
}

@test "Loki holds a Guardrail event for the Swarm" {
  eventually 120 loki_positive "sum(count_over_time({event_type=\"process_kprobe\", swarm=\"$SWARM\", policy=~\"guardrail-.+\"}[3h]))"
}

@test "Loki holds a failed Task event with exit 137 (the Task a Guardrail killed)" {
  eventually 120 loki_positive "sum(count_over_time({event_type=\"task_event\", swarm=\"$SWARM\", state=\"failed\"} | json | exit=\"137\" [3h]))"
}

@test "Loki holds succeeded Task events (the benign Scenarios)" {
  eventually 120 loki_positive "sum(count_over_time({event_type=\"task_event\", swarm=\"$SWARM\", state=\"succeeded\"}[3h]))"
}

@test "Loki holds Swarm exec events" {
  eventually 120 loki_positive "sum(count_over_time({event_type=\"process_exec\", swarm=\"$SWARM\"}[3h]))"
}

@test "Prometheus scrapes Tetragon's event metrics" {
  eventually 120 prom_has_series 'tetragon_events_total{event_type="PROCESS_KPROBE"}'
}

@test "Prometheus counts the Guardrail policy hits" {
  eventually 120 prom_has_series "tetragon_policy_events_total{policy=~\"guardrail-.+\", namespace=\"swarm-$SWARM\"}"
}
