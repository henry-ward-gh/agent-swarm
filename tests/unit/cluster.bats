#!/usr/bin/env bats
# guardrails_loaded against a fake kubectl: it must never pass by looking at nothing.

setup() {
  load ../lib/cluster
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"
  export NODES=2 PODS="pod/tetragon-a pod/tetragon-b" STATES="enabled enabled enabled" LOG=""
  cat >"$BIN/kubectl" <<'SH'
#!/usr/bin/env bash
args="$*"
case "$args" in
  *"get nodes"*) for _ in $(seq 1 "$NODES"); do echo node/x; done ;;
  *"get pods"*) for p in $PODS; do echo "$p"; done ;;
  *"tetra tracingpolicy list"*)
    echo "ID NAME DOMAIN STATE FILTERID NAMESPACE SENSORS"
    i=1
    for g in guardrail-egress guardrail-credential-files guardrail-workspace-exec; do
      state=$(cut -d' ' -f"$i" <<<"$STATES"); echo "$i $g k8s $state 0 swarm-demo generic_kprobe"; i=$((i + 1))
    done ;;
  *"logs"*) echo "$LOG" ;;
esac
SH
  chmod +x "$BIN/kubectl"
}

@test "passes when every Guardrail is enabled on every agent" {
  run guardrails_loaded
  [ "$status" -eq 0 ]
}

@test "fails when no Tetragon agent is found" {
  PODS="" run guardrails_loaded
  [ "$status" -ne 0 ]
  [[ "$output" == *"no Tetragon agents"* ]]
}

@test "fails when an agent is missing from a node" {
  NODES=3 run guardrails_loaded
  [ "$status" -ne 0 ]
  [[ "$output" == *"2 Tetragon agent(s) for 3 node(s)"* ]]
}

@test "fails when a Guardrail is in load_error" {
  STATES="enabled load_error enabled" run guardrails_loaded
  [ "$status" -ne 0 ]
  [[ "$output" == *"guardrail-credential-files is 'load_error'"* ]]
}

@test "fails when Tetragon logged a rejected policy" {
  LOG="level=error msg=\"failed loading policy 'guardrail-egress'\"" run guardrails_loaded
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed loading policy"* ]]
}
