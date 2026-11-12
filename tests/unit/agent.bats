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
