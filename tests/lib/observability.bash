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
