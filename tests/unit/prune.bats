#!/usr/bin/env bats
# GHCR retention (scripts/ghcr-prune.sh): which package versions get deleted.

setup() {
  load ../../scripts/ghcr-prune.sh
  VERSIONS="$BATS_TEST_TMPDIR/versions.json"
  # newest first in time: 5 (main,latest), 4 (sha), 3 (untagged signature), 2 (sha), 1 (sha, oldest)
  cat >"$VERSIONS" <<'JSON'
[
  {"id": 2, "created_at": "2026-11-12T10:00:00Z", "metadata": {"container": {"tags": ["aaa2"]}}},
  {"id": 5, "created_at": "2026-11-12T13:00:00Z", "metadata": {"container": {"tags": ["main", "latest", "aaa5"]}}},
  {"id": 1, "created_at": "2026-11-12T09:00:00Z", "metadata": {"container": {"tags": ["aaa1"]}}},
  {"id": 3, "created_at": "2026-11-12T11:00:00Z", "metadata": {"container": {"tags": []}}},
  {"id": 4, "created_at": "2026-11-12T12:00:00Z", "metadata": {"container": {"tags": ["aaa4"]}}}
]
JSON
}

@test "keeps the newest N versions and prunes the rest, oldest last" {
  run select_prunable 3 <"$VERSIONS"
  [ "$status" -eq 0 ]
  [ "$output" = $'2\n1' ]
}

@test "prunes nothing when there are fewer versions than the limit" {
  run select_prunable 10 <"$VERSIONS"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "never prunes a version tagged main or latest, even past the limit" {
  run select_prunable 1 <"$VERSIONS"
  [ "$status" -eq 0 ]
  [[ "$output" != *$'\n5'* && "$output" != "5"* ]]
  [ "$output" = $'4\n3\n2\n1' ]
}

@test "rejects a non-numeric keep count" {
  run select_prunable lots <"$VERSIONS"
  [ "$status" -ne 0 ]
}

@test "malformed input is an error, not an empty selection" {
  run select_prunable 3 <<<'not json'
  [ "$status" -ne 0 ]
}

fake_gh() {
  mkdir -p "$BATS_TEST_TMPDIR/bin"
  cat >"$BATS_TEST_TMPDIR/bin/gh" <<'SH'
#!/usr/bin/env bash
echo "$*" >>"$GH_CALLS"
case "$*" in
  "api users/someone -q .type") echo User ;;
  *"--paginate"*) cat "$VERSIONS" ;;
esac
SH
  chmod +x "$BATS_TEST_TMPDIR/bin/gh"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH" GH_CALLS="$BATS_TEST_TMPDIR/gh.calls" VERSIONS
  : >"$GH_CALLS"
}

@test "dry run lists what it would delete and deletes nothing" {
  fake_gh
  run "$BATS_TEST_DIRNAME/../../scripts/ghcr-prune.sh" someone agent-swarm/mock-agent 3 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"would delete version 2"* && "$output" == *"would delete version 1"* ]]
  run grep -c DELETE "$GH_CALLS"
  [ "$output" = "0" ]
  grep -q 'users/someone/packages/container/agent-swarm%2Fmock-agent/versions' "$GH_CALLS"
}

@test "a real run deletes exactly the pruned versions" {
  fake_gh
  run "$BATS_TEST_DIRNAME/../../scripts/ghcr-prune.sh" someone agent-swarm/mock-agent 3
  [ "$status" -eq 0 ]
  [ "$(grep -c -- '-X DELETE' "$GH_CALLS")" -eq 2 ]
  grep -q -- '-X DELETE users/someone/packages/container/agent-swarm%2Fmock-agent/versions/2' "$GH_CALLS"
  grep -q -- '-X DELETE users/someone/packages/container/agent-swarm%2Fmock-agent/versions/1' "$GH_CALLS"
}
