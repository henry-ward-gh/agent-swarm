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

# guardrail_hits <events.jsonl> <policy|""> <namespace> <worker> <start> <finish> [slack-seconds] [floor]
# Counts enforcing Guardrail events for that Worker inside [start - slack, finish + slack], compared
# to the millisecond. Slack only absorbs clock skew between the Worker's `date` and Tetragon's
# timestamps. A Worker can start its next Task under 50 ms after the last one was killed, so the slack
# alone would blame a Task for its neighbour's kill: an event at or before `floor` (the previous Task's
# finishedAt on that Worker, see previous_finish) belongs to that Task and is never counted.
# An empty policy matches any guardrail-* policy.
guardrail_hits() {
  local events="$1" policy="$2" ns="$3" worker="$4" start="$5" finish="$6" slack="${7:-0.05}" floor="${8:-}" matches
  # Fail loudly if jq can't read the log: counting a failed run's output would turn "unreadable" into
  # "zero events" (passing a benign Task) or into a partial count.
  matches=$(jq -c --arg p "$policy" --arg ns "$ns" --arg w "$worker" --arg s "$start" --arg f "$finish" --arg floor "$floor" --argjson slack "$slack" '
    def secs: (sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601)
      + ((capture("\\.(?<f>[0-9]+)Z$") // {f: "0"}).f | ("0." + .) | tonumber);
    select(.process_kprobe != null
      and (if $p == "" then (.process_kprobe.policy_name | startswith("guardrail-")) else .process_kprobe.policy_name == $p end)
      and .process_kprobe.process.pod.namespace == $ns
      and .process_kprobe.process.pod.name == $w
      and (.process_kprobe.action | IN("KPROBE_ACTION_SIGKILL", "KPROBE_ACTION_OVERRIDE"))
      and (.time | secs) >= (($s | secs) - $slack) and (.time | secs) <= (($f | secs) + $slack)
      and ($floor == "" or (.time | secs) > ($floor | secs)))' "$events") || return 1
  if [[ -z "$matches" ]]; then
    echo 0
  else
    wc -l <<<"$matches" | tr -d ' '
  fi
}

# previous_finish <results-json-array> <index> — finishedAt of the latest earlier Task on the same
# Worker as Task <index> (one that finished by the time it started), or nothing if there is none.
previous_finish() {
  jq -r --argjson i "$2" '
    .[$i] as $t
    | [.[] | select(.worker == $t.worker and .finishedAt != null and .finishedAt <= $t.startedAt) | .finishedAt]
    | max // empty' <<<"$1"
}

# verdict <expect> <result-json> <events.jsonl> <namespace> [floor]
# Prints why on failure. Exit 0 = the Task did what its Scenario declared.
# floor: the previous Task's finishedAt on the same Worker (previous_finish), so its kill is not counted.
verdict() {
  local expect="$1" result="$2" events="$3" ns="$4" floor="${5:-}"
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
      if ! hits=$(guardrail_hits "$events" "" "$ns" "$worker" "$start" "$finish" 0.05 "$floor"); then
        echo "could not read the Tetragon events in $events"
        return 1
      fi
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
      if ! hits=$(guardrail_hits "$events" "$policy" "$ns" "$worker" "$start" "$finish" 0 "$floor"); then
        echo "could not read the Tetragon events in $events"
        return 1
      fi
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
