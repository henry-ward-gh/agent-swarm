#!/usr/bin/env bats
# The Loki/Prometheus response parsing and polling helpers, with a fake kubectl (no cluster).

setup() {
  load ../lib/observability
  BIN="$BATS_TEST_TMPDIR/bin"; mkdir -p "$BIN"
  export PATH="$BIN:$PATH"
}

fake_kubectl() { # <response-json>
  printf '#!/usr/bin/env bash\necho "$*" >>"%s/args"\ncat <<'"'"'JSON'"'"'\n%s\nJSON\n' "$BATS_TEST_TMPDIR" "$1" >"$BIN/kubectl"
  chmod +x "$BIN/kubectl"
}

@test "vector_total sums the samples and treats no result as zero" {
  [ "$(vector_total '{"data":{"result":[{"value":[1,"2"]},{"value":[1,"3"]}]}}')" = "5" ]
  [ "$(vector_total '{"data":{"result":[]}}')" = "0" ]
}

@test "series_count counts series" {
  [ "$(series_count '{"data":{"result":[{},{}]}}')" = "2" ]
}

@test "loki_positive is true only for a positive total, and URL-encodes the query" {
  fake_kubectl '{"data":{"result":[{"value":[1,"1"]}]}}'
  loki_positive 'sum(count_over_time({event_type="process_kprobe"}[2h]))'
  grep -q '/services/loki:3100/proxy/loki/api/v1/query?query=sum%28count_over_time%28%7Bevent_type%3D%22process_kprobe%22%7D%5B2h%5D%29%29' "$BATS_TEST_TMPDIR/args"
  fake_kubectl '{"data":{"result":[{"value":[1,"0"]}]}}'
  run loki_positive 'x'
  [ "$status" -ne 0 ]
}

@test "prom_has_series needs at least one series" {
  fake_kubectl '{"data":{"result":[{"metric":{}}]}}'
  prom_has_series 'tetragon_events_total'
  fake_kubectl '{"data":{"result":[]}}'
  run prom_has_series 'tetragon_events_total'
  [ "$status" -ne 0 ]
}

@test "a failing kubectl is a failure, not zero" {
  printf '#!/usr/bin/env bash\nexit 1\n' >"$BIN/kubectl"; chmod +x "$BIN/kubectl"
  run loki_positive 'x'
  [ "$status" -ne 0 ]
}

@test "eventually retries until the command passes, and gives up after the timeout" {
  sleep() { :; }
  n=0; flaky() { n=$((n + 1)); [[ $n -ge 3 ]]; }
  eventually 5 flaky
  run eventually 0 false
  [ "$status" -ne 0 ]
}

@test "dashboard_loki_exprs fills in Grafana's variables and skips other datasources" {
  cat >"$BATS_TEST_TMPDIR/d.json" <<'JSON'
{"panels":[
 {"targets":[{"datasource":{"type":"loki"},"expr":"sum(count_over_time({swarm=~\"$swarm\", role=~\"$role\"}[$__range]))"}]},
 {"targets":[{"datasource":{"type":"prometheus"},"expr":"up"}]},
 {"targets":[{"datasource":{"type":"loki"},"expr":"count_over_time({swarm=\"x\"}[$__interval])"}]}
]}
JSON
  run dashboard_loki_exprs "$BATS_TEST_TMPDIR/d.json" demo
  [ "${lines[0]}" = 'sum(count_over_time({swarm=~"demo", role=~".*"}[1h]))' ]
  [ "${lines[1]}" = 'count_over_time({swarm="x"}[1m])' ]
  [ "${#lines[@]}" -eq 2 ]
}
