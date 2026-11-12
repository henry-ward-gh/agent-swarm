# shellcheck shell=bash
# What the harness asks Loki and Prometheus (through the API server's service proxy, so no port-forward).

# vector_total <query-response-json> — sum of an instant query's sample values; 0 when it returned none.
vector_total() {
  jq -r '[.data.result[]?.value[1] | tonumber] | add // 0' <<<"$1"
}

# series_count <query-response-json> — number of series an instant query returned.
series_count() {
  jq -r '.data.result | length' <<<"$1"
}

_proxy_query() { # <service:port> <api path> <expr>
  kubectl get --raw "/api/v1/namespaces/monitoring/services/$1/proxy$2?query=$(jq -rn --arg q "$3" '$q | @uri')"
}

loki_query() { _proxy_query loki:3100 /loki/api/v1/query "$1"; }
prom_query() { _proxy_query kube-prometheus-stack-prometheus:http-web /api/v1/query "$1"; }

# loki_positive <logql> — the metric query's total is above zero.
loki_positive() {
  local out
  out=$(loki_query "$1") || return 1
  awk -v n="$(vector_total "$out")" 'BEGIN { exit !(n > 0) }'
}

# prom_has_series <promql> — the query returns at least one series.
prom_has_series() {
  local out
  out=$(prom_query "$1") || return 1
  [[ "$(series_count "$out")" -gt 0 ]]
}

# eventually <seconds> <command...> — retry every 3 s; Alloy, Loki and Prometheus all ingest a moment late.
eventually() {
  local deadline=$((SECONDS + $1))
  shift
  until "$@"; do
    ((SECONDS < deadline)) || { echo "still failing after the timeout: $*"; return 1; }
    sleep 3
  done
}

# dashboard_loki_exprs <dashboard.json> <swarm> — every Loki query in the dashboard, with Grafana's variables
# filled in (both Agent roles, a 1 h range, a 1 m interval).
dashboard_loki_exprs() {
  jq -r --arg swarm "$2" '.panels[].targets[]? | select(.datasource.type == "loki") | .expr
    | gsub("\\$swarm"; $swarm) | gsub("\\$role"; "orchestrator|worker") | gsub("\\$__range"; "1h") | gsub("\\$__interval"; "1m")' "$1"
}

# loki_range_ok <logql> — Loki accepts the query (as a range query, so log and metric queries both work).
loki_range_ok() {
  local now out
  now=$(date +%s)
  out=$(kubectl get --raw "/api/v1/namespaces/monitoring/services/loki:3100/proxy/loki/api/v1/query_range?query=$(jq -rn --arg q "$1" '$q | @uri')&start=$((now - 3600))&end=$now&step=60&limit=5") || return 1
  [[ "$(jq -r .status <<<"$out")" == "success" ]]
}

# ---- Grafana (needs a port-forward: its API wants credentials, which the API server's service proxy can't send) ----

GRAFANA_PORT="${GRAFANA_PORT:-13000}"

# grafana_forward_start — port-forward to Grafana in the background; the pid is left in GRAFANA_PF_PID.
grafana_forward_start() {
  kubectl -n monitoring port-forward svc/kube-prometheus-stack-grafana "$GRAFANA_PORT:80" >/dev/null 2>&1 &
  GRAFANA_PF_PID=$!
  export GRAFANA_PF_PID
}

grafana_forward_stop() { [[ -z "${GRAFANA_PF_PID:-}" ]] || kill "$GRAFANA_PF_PID" 2>/dev/null || true; }

# grafana_get <path> — GET against Grafana as the demo admin (the platform app sets admin / admin).
grafana_get() {
  curl -fsS -u admin:admin "http://127.0.0.1:$GRAFANA_PORT$1"
}

# grafana_succeeds <path> — GET succeeds and, if it's a Loki/Prometheus API response, reports status "success".
grafana_succeeds() {
  # The forward dies if it was started before Grafana was ready: bring it back rather than fail forever.
  kill -0 "${GRAFANA_PF_PID:-0}" 2>/dev/null || { grafana_forward_start; sleep 2; }
  grafana_get "$1" | jq -e '(.status // "success") == "success"' >/dev/null
}
