#!/usr/bin/env bats
# The Swarm activity pipeline on a live cluster (task up first). Runs after guardrails.bats (alphabetical),
# so every rogue Goal has already been played: Tetragon's events and the Agents' Task events must have
# reached Loki, and Prometheus must be scraping Tetragon. Ingest is asynchronous, hence `eventually`.

setup() {
  load ../lib/observability
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  SWARM="${SWARM_NAMESPACE:-swarm-demo}"
  SWARM="${SWARM#swarm-}"
}

# swarm_events <stream selector> [pipeline] — count of this Swarm's matching events in the last 3 h.
swarm_events() { echo "sum(count_over_time({swarm=\"$SWARM\", $1} ${2:-} [3h]))"; }

@test "Loki holds a Guardrail event for the Swarm" {
  eventually 120 loki_positive "$(swarm_events 'event_type="process_kprobe", policy=~"guardrail-.+"')"
}

@test "Loki holds a failed Task event with exit 137 (the Task a Guardrail killed)" {
  eventually 120 loki_positive "$(swarm_events 'event_type="task_event", state="failed"' '| json | exit="137"')"
}

@test "Loki holds succeeded Task events (the benign Scenarios)" {
  eventually 120 loki_positive "$(swarm_events 'event_type="task_event", state="succeeded"')"
}

@test "Loki holds Swarm exec events" {
  eventually 120 loki_positive "$(swarm_events 'event_type="process_exec"')"
}

@test "Prometheus scrapes Tetragon's event metrics" {
  eventually 120 prom_has_series 'tetragon_events_total{event_type="PROCESS_KPROBE"}'
}

@test "Prometheus counts the Guardrail policy hits" {
  eventually 120 prom_has_series 'tetragon_policy_events_total{policy=~"guardrail-.+"}'
}

@test "every Loki query in the Swarm activity dashboard is valid LogQL" {
  local expr n=0
  while IFS= read -r expr; do
    n=$((n + 1))
    run loki_range_ok "$expr"
    [ "$status" -eq 0 ] || { echo "Loki rejected: $expr"; return 1; }
  done < <(dashboard_loki_exprs "$REPO_ROOT/gitops/platform/observability/files/swarm-activity.json" "$SWARM")
  [ "$n" -ge 6 ]
}
