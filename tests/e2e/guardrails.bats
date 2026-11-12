#!/usr/bin/env bats
# End-to-end Guardrail tests on a live cluster (task up first; see tests/README.md).
# One test per Goal plan in agents/mock/goals/: submit the plan, then judge every Task against
# the `# expect:` header of its Scenario. Adding a Scenario (and a plan of the same name) adds a test.

setup() {
  load ../lib/verdict
  load ../lib/cluster
  ARTIFACTS="${E2E_ARTIFACTS:-$REPO_ROOT/tests/results}"
  mkdir -p "$ARTIFACTS"
}

@test "every Guardrail is loaded on every Tetragon agent" {
  run guardrails_loaded
  echo "$output"
  [ "$status" -eq 0 ]
}

# check_plan <plan> — run the Goal, then apply the verdict to each Task in plan order.
check_plan() {
  local plan="$1" out results scenarios i n expect attempt failures sink=0
  out=$("$REPO_ROOT/scripts/goal.sh" "$plan" --wait 150) || { echo "goal.sh $plan failed (exit $?)"; return 1; }
  results=$(tail -n +2 <<<"$out")
  printf '%s\n' "$results" >"$ARTIFACTS/results-$plan.json"

  mapfile -t scenarios < <(plan_scenarios "$REPO_ROOT/agents/mock/goals/$plan.txt")
  n=${#scenarios[@]}
  if [[ "$(jq 'length' <<<"$results")" -ne "$n" ]]; then
    echo "expected $n Results for $plan, got: $results"
    return 1
  fi

  # Tetragon exports events a moment after they happen: retry the verdict before giving up.
  for attempt in 1 2 3 4 5 6; do
    sleep 4
    collect_events "$ARTIFACTS/events-$plan.jsonl"
    failures=""
    for ((i = 0; i < n; i++)); do
      expect=$(scenario_expect "$REPO_ROOT/agents/mock/scenarios/${scenarios[$i]}.sh") || return 1
      if ! why=$(verdict "$expect" "$(jq -c ".[$i]" <<<"$results")" "$ARTIFACTS/events-$plan.jsonl" "$SWARM_NAMESPACE"); then
        failures+="${scenarios[$i]}: $why"$'\n'
      fi
      [[ "$expect" == "blocked guardrail-egress" ]] && sink=1
    done
    [[ -z "$failures" ]] && break
  done
  if [[ -n "$failures" ]]; then
    printf '%s' "$failures"
    return 1
  fi

  # Second, independent proof for exfiltration: nothing reached the Exfil Sink.
  if [[ "$sink" -eq 1 ]]; then
    sink_empty "$(sink_received)" || return 1
  fi
}

# `smoke` first, so a broken Swarm fails fast; then every other plan (benign, rogue, demo).
plans=(smoke)
for plan_file in "$BATS_TEST_DIRNAME"/../../agents/mock/goals/*.txt; do
  plan=$(basename "$plan_file" .txt)
  [[ "$plan" == smoke ]] || plans+=("$plan")
done
for plan in "${plans[@]}"; do
  bats_test_function --description "Goal $plan: every Task does what its Scenario declares" -- check_plan "$plan"
done
