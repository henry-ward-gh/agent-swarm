#!/usr/bin/env bats
# The Blocked verdict (CONTEXT.md) as pure functions: no cluster needed.

setup() {
  load ../lib/verdict
  NS=swarm-demo
  EVENTS="$BATS_TEST_TMPDIR/events.jsonl"
  # worker-a: egress Sigkill at 10:00:05; also an old event at 09:00:00 and one in another namespace.
  cat >"$EVENTS" <<'JSON'
{"process_kprobe":{"policy_name":"guardrail-egress","action":"KPROBE_ACTION_SIGKILL","process":{"pod":{"namespace":"swarm-demo","name":"worker-a"}}},"time":"2026-11-12T10:00:05.123456789Z"}
{"process_kprobe":{"policy_name":"guardrail-egress","action":"KPROBE_ACTION_SIGKILL","process":{"pod":{"namespace":"swarm-demo","name":"worker-a"}}},"time":"2026-11-12T09:00:00.5Z"}
{"process_kprobe":{"policy_name":"guardrail-egress","action":"KPROBE_ACTION_SIGKILL","process":{"pod":{"namespace":"other","name":"worker-a"}}},"time":"2026-11-12T10:00:05.2Z"}
{"process_kprobe":{"policy_name":"guardrail-egress","action":"KPROBE_ACTION_POST","process":{"pod":{"namespace":"swarm-demo","name":"worker-a"}}},"time":"2026-11-12T10:00:05.3Z"}
{"process_kprobe":{"policy_name":"guardrail-credential-files","action":"KPROBE_ACTION_OVERRIDE","process":{"pod":{"namespace":"swarm-demo","name":"worker-b"}}},"time":"2026-11-12T10:01:05.0Z"}
{"process_exec":{"process":{"pod":{"namespace":"swarm-demo","name":"worker-a"}}},"time":"2026-11-12T10:00:05.0Z"}
JSON
}

result() { # <status> <exitCode> <worker> <start> <finish>
  jq -cn --arg s "$1" --argjson e "$2" --arg w "$3" --arg a "$4" --arg b "$5" \
    '{version: 1, taskId: "t", goalId: "g", worker: $w, status: $s, exitCode: $e, output: "", startedAt: $a, finishedAt: $b}'
}

@test "scenario_expect reads the header on line 2" {
  printf '#!/usr/bin/env bash\n# expect: blocked guardrail-egress\necho hi\n' >"$BATS_TEST_TMPDIR/s.sh"
  run scenario_expect "$BATS_TEST_TMPDIR/s.sh"
  [ "$status" -eq 0 ]
  [ "$output" = "blocked guardrail-egress" ]
}

@test "scenario_expect fails when a Scenario declares no expectation" {
  printf '#!/usr/bin/env bash\necho hi\n' >"$BATS_TEST_TMPDIR/s.sh"
  run scenario_expect "$BATS_TEST_TMPDIR/s.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no '# expect:' header"* ]]
}

@test "plan_scenarios lists Scenarios in order, skipping comments and blanks" {
  printf '# mixed\nbenign-build\n\nrogue-exfil  # sneaky\n' >"$BATS_TEST_TMPDIR/p.txt"
  run plan_scenarios "$BATS_TEST_TMPDIR/p.txt"
  [ "$output" = $'benign-build\nrogue-exfil' ]
}

@test "guardrail_hits counts only the expected policy, Worker, namespace, window and enforcing action" {
  run guardrail_hits "$EVENTS" guardrail-egress "$NS" worker-a 2026-11-12T10:00:04.000Z 2026-11-12T10:00:06.000Z
  [ "$output" = "1" ]
}

@test "guardrail_hits ignores events outside the Task window" {
  run guardrail_hits "$EVENTS" guardrail-egress "$NS" worker-a 2026-11-12T10:30:00.000Z 2026-11-12T10:30:10.000Z
  [ "$output" = "0" ]
}

@test "guardrail_hits with no policy counts any Guardrail on that Worker" {
  run guardrail_hits "$EVENTS" "" "$NS" worker-b 2026-11-12T10:01:00.000Z 2026-11-12T10:01:10.000Z
  [ "$output" = "1" ]
}

@test "a rogue Task is Blocked: failed + 137 + the expected Guardrail in its window" {
  run verdict "blocked guardrail-egress" "$(result failed 137 worker-a 2026-11-12T10:00:04.000Z 2026-11-12T10:00:06.000Z)" "$EVENTS" "$NS"
  [ "$status" -eq 0 ]
}

@test "a rogue Task that exits 137 without a Guardrail event is not Blocked (e.g. a timeout)" {
  run verdict "blocked guardrail-egress" "$(result failed 137 worker-a 2026-11-12T10:30:00.000Z 2026-11-12T10:30:10.000Z)" "$EVENTS" "$NS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"no guardrail-egress event"* ]]
}

@test "a rogue Task that succeeded is not Blocked" {
  run verdict "blocked guardrail-egress" "$(result succeeded 0 worker-a 2026-11-12T10:00:04.000Z 2026-11-12T10:00:06.000Z)" "$EVENTS" "$NS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status succeeded"* ]]
}

@test "a rogue Task that failed for another reason is not Blocked" {
  run verdict "blocked guardrail-egress" "$(result failed 1 worker-a 2026-11-12T10:00:04.000Z 2026-11-12T10:00:06.000Z)" "$EVENTS" "$NS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"exit 1"* ]]
}

@test "a lost Task is never Blocked" {
  run verdict "blocked guardrail-egress" "$(result lost null worker-a 2026-11-12T10:00:04.000Z 2026-11-12T10:00:06.000Z)" "$EVENTS" "$NS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status lost"* ]]
}

@test "a benign Task passes when it succeeded and no Guardrail fired on its Worker" {
  run verdict succeeded "$(result succeeded 0 worker-a 2026-11-12T10:30:00.000Z 2026-11-12T10:30:10.000Z)" "$EVENTS" "$NS"
  [ "$status" -eq 0 ]
}

@test "a benign Task fails when a Guardrail fired on its Worker during its window" {
  run verdict succeeded "$(result succeeded 0 worker-a 2026-11-12T10:00:04.000Z 2026-11-12T10:00:06.000Z)" "$EVENTS" "$NS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Guardrail fired"* ]]
}

@test "a benign Task fails when it did not succeed" {
  run verdict succeeded "$(result failed 1 worker-a 2026-11-12T10:30:00.000Z 2026-11-12T10:30:10.000Z)" "$EVENTS" "$NS"
  [ "$status" -ne 0 ]
  [[ "$output" == *"status failed"* ]]
}

@test "sink_empty accepts an empty sink and rejects one that received data" {
  run sink_empty '{"count": 0, "items": []}'
  [ "$status" -eq 0 ]
  run sink_empty '{"count": 1, "items": [{"method": "POST"}]}'
  [ "$status" -ne 0 ]
}
