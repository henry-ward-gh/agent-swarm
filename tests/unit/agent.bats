#!/usr/bin/env bats
# Mock Agent runtime against a fake valkey-cli (no broker, no cluster).

setup() {
  AGENT="$BATS_TEST_DIRNAME/../../agents/mock/bin/agent"
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"
  export CALLS="$BATS_TEST_TMPDIR/calls.log"
  : >"$CALLS"
  # Logs each command when it COMPLETES. SET is slow and BLMOVE instant, so if a Worker claims a Task
  # without waiting for its first heartbeat, BLMOVE is logged first.
  cat >"$BIN/valkey-cli" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *" SET "*) sleep 0.4 ;;
  *BLMOVE*) sleep 0.05 ;;
esac
echo "$args" >>"$CALLS"
SH
  chmod +x "$BIN/valkey-cli"
}

@test "a Worker's first heartbeat lands before it claims any Task (or the Orchestrator reaps the claim as lost)" {
  # setsid: the agent's EXIT trap does `kill 0`, which must not reach bats.
  AGENT_ROLE=worker VALKEY_HOST=fake POD_NAME=w1 WORKSPACE="$BATS_TEST_TMPDIR/ws" \
    setsid -w timeout 2 "$AGENT" run || true
  first=$(grep -m1 -E "SET heartbeat:|BLMOVE" "$CALLS")
  [[ "$first" == *"SET heartbeat:w1"* ]]
}

# ---- Task-transition lines (protocol/task-event.schema.json) ----

# A fake broker that hands out one Task, then goes quiet; reports `w9` as a dead Worker holding one.
task_broker() {
  cat >"$BIN/valkey-cli" <<'SH'
#!/usr/bin/env bash
args="$*"
TASK='{"version":1,"id":"t-1","goalId":"g-1","scenario":"'"${SCENARIO:-ok}"'","inputs":{}}'
case "$args" in
  *BLMOVE*) if [[ ! -e "$BATS_TEST_TMPDIR/claimed" ]]; then touch "$BATS_TEST_TMPDIR/claimed"; echo "$TASK"; else sleep 1; fi ;;
  *"--scan"*) echo "running:w9" ;;
  *EXISTS*) echo 0 ;;
  *LRANGE*) echo "$TASK" ;;
  *BRPOP*) sleep 1 ;;
esac
SH
  chmod +x "$BIN/valkey-cli"
  export AGENT_HOME="$BATS_TEST_TMPDIR/home"; mkdir -p "$AGENT_HOME/scenarios"
  printf 'exit 0\n' >"$AGENT_HOME/scenarios/ok.sh"
  printf 'exit 137\n' >"$AGENT_HOME/scenarios/killed.sh"
}

run_agent() { # <role> -> JSON lines on stdout in $BATS_TEST_TMPDIR/events
  AGENT_ROLE="$1" SWARM_NAME=demo VALKEY_HOST=fake POD_NAME=w1 WORKSPACE="$BATS_TEST_TMPDIR/ws" \
    setsid -w timeout 3 "$AGENT" run >"$BATS_TEST_TMPDIR/events" 2>/dev/null || true
}

events() { jq -c 'select(.task_id)' "$BATS_TEST_TMPDIR/events"; }

@test "a Worker logs started then succeeded for a Task that exits 0" {
  task_broker
  run_agent worker
  [[ "$(events | jq -r .state | paste -sd,)" == "started,succeeded" ]]
  run jq -e 'select(.state=="succeeded") | .swarm=="demo" and .role=="worker" and .task_id=="t-1" and .scenario=="ok" and .exit==0 and (.ts|test("^[0-9]{4}-.*Z$"))' "$BATS_TEST_TMPDIR/events"
  [ "$status" -eq 0 ]
}

@test "a Worker logs failed with the exit code when the Scenario is killed" {
  task_broker
  SCENARIO=killed run_agent worker
  [[ "$(events | jq -r .state | paste -sd,)" == "started,failed" ]]
  [[ "$(events | jq -r 'select(.state=="failed") | .exit')" == "137" ]]
}

@test "the Orchestrator logs lost, with a null exit, for a Task whose Worker stopped" {
  task_broker
  run_agent orchestrator
  [[ "$(events | jq -r .state | sort -u)" == "lost" ]]
  [[ "$(events | jq -r '.exit' | sort -u)" == "null" ]]
  [[ "$(events | jq -r '.role' | sort -u)" == "orchestrator" ]]
}

@test "every task-event line is a single valid JSON object with exactly the contracted fields" {
  task_broker
  run_agent worker
  events | jq -e 'keys == ["exit","role","scenario","state","swarm","task_id","ts","worker"]' >/dev/null
}
