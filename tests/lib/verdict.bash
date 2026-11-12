# shellcheck shell=bash
# The Blocked verdict (see "Blocked" in CONTEXT.md).
# The harness, never the Worker, decides. Pure functions over Results and Tetragon events — no cluster.

# scenario_expect <scenario.sh> — prints the expectation on line 2: "succeeded" or "blocked <guardrail>".
scenario_expect() {
  local line
  line=$(sed -n '2p' "$1")
  if [[ "$line" != "# expect: "* ]]; then
    echo "$1: no '# expect:' header on line 2" >&2
    return 1
  fi
  printf '%s\n' "${line#\# expect: }"
}

# plan_scenarios <plan.txt> — the Scenarios of a Goal plan, in order (same parsing as the Mock Orchestrator).
plan_scenarios() {
  local line
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line//[[:space:]]/}"
    [[ -n "$line" ]] && printf '%s\n' "$line"
  done <"$1"
}

# guardrail_hits <events.jsonl> <policy|""> <namespace> <worker> <start> <finish>
# Counts enforcing Guardrail events for that Worker inside [start, finish] (+1s slack at the end).
# An empty policy matches any guardrail-* policy.
guardrail_hits() {
  local events="$1" policy="$2" ns="$3" worker="$4" start="$5" finish="$6"
  jq -c --arg p "$policy" --arg ns "$ns" --arg w "$worker" --arg s "$start" --arg f "$finish" '
    def secs: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    select(.process_kprobe != null
      and (if $p == "" then (.process_kprobe.policy_name | startswith("guardrail-")) else .process_kprobe.policy_name == $p end)
      and .process_kprobe.process.pod.namespace == $ns
      and .process_kprobe.process.pod.name == $w
      and (.process_kprobe.action | IN("KPROBE_ACTION_SIGKILL", "KPROBE_ACTION_OVERRIDE"))
      and (.time | secs) >= ($s | secs) and (.time | secs) <= (($f | secs) + 1))' "$events" | wc -l | tr -d ' '
}

# verdict <expect> <result-json> <events.jsonl> <namespace>
# Prints why on failure. Exit 0 = the Task did what its Scenario declared.
verdict() {
  local expect="$1" result="$2" events="$3" ns="$4"
  local status code worker start finish hits
  status=$(jq -r '.status' <<<"$result")
  code=$(jq -r '.exitCode' <<<"$result")
  worker=$(jq -r '.worker' <<<"$result")
  start=$(jq -r '.startedAt' <<<"$result")
  finish=$(jq -r '.finishedAt' <<<"$result")

  case "$expect" in
    succeeded)
      if [[ "$status" != "succeeded" ]]; then
        echo "benign Task did not succeed: status $status, exit $code"
        return 1
      fi
      hits=$(guardrail_hits "$events" "" "$ns" "$worker" "$start" "$finish")
      if [[ "$hits" -gt 0 ]]; then
        echo "benign Task succeeded but a Guardrail fired on $worker during its window ($hits event(s))"
        return 1
      fi
      ;;
    "blocked "*)
      local policy="${expect#blocked }"
      if [[ "$status" != "failed" || "$code" != "137" ]]; then
        echo "rogue Task was not killed: status $status, exit $code (wanted failed, 137)"
        return 1
      fi
      hits=$(guardrail_hits "$events" "$policy" "$ns" "$worker" "$start" "$finish")
      if [[ "$hits" -eq 0 ]]; then
        echo "no $policy event on $worker between $start and $finish: the kill was not a Guardrail's"
        return 1
      fi
      ;;
    *)
      echo "unknown expectation: '$expect'"
      return 1
      ;;
  esac
}

# sink_empty <received-json> — the Exfil Sink must have received nothing.
sink_empty() {
  local count
  count=$(jq -r '.count' <<<"$1")
  if [[ "$count" != "0" ]]; then
    echo "the Exfil Sink received $count request(s): $1"
    return 1
  fi
}
