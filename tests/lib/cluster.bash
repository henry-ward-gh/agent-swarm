# shellcheck shell=bash
# Everything the e2e harness needs from a live cluster. The verdict itself is in verdict.bash.

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
export REPO_ROOT
export SWARM_NAMESPACE="${SWARM_NAMESPACE:-swarm-demo}"
GUARDRAILS=(guardrail-egress guardrail-credential-files guardrail-workspace-exec)

tetragon_pods() { kubectl -n kube-system get pods -l app.kubernetes.io/name=tetragon -o name; }

# collect_events <file> — every kprobe event Tetragon has exported, from every node's agent.
collect_events() {
  kubectl -n kube-system logs -l app.kubernetes.io/name=tetragon -c export-stdout \
    --tail=-1 --max-log-requests=20 >"$1"
}

sink_received() {
  kubectl -n outside-world exec deploy/exfil-sink -- python -c \
    "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/received').read().decode())"
}

# guardrails_loaded — every Guardrail is enabled on every Tetragon agent, and none failed to load.
# A rejected policy still shows as a created CRD, so ask each agent rather than the API server.
guardrails_loaded() {
  local pod pods listing g state rc=0 nodes agents
  pods=$(tetragon_pods) || { echo "could not list Tetragon agents"; return 1; }
  nodes=$(kubectl get nodes -o name | wc -l | tr -d ' ')
  agents=$(grep -c . <<<"$pods" || true)
  if [[ "$agents" -eq 0 ]]; then
    echo "no Tetragon agents found"
    return 1
  fi
  if [[ "$agents" -ne "$nodes" ]]; then
    echo "$agents Tetragon agent(s) for $nodes node(s): the DaemonSet is not on every node"
    return 1
  fi
  for pod in $pods; do
    listing=$(kubectl -n kube-system exec "$pod" -c tetragon -- tetra tracingpolicy list) || return 1
    for g in "${GUARDRAILS[@]}"; do
      state=$(awk -v g="$g" '$2 == g {print $4}' <<<"$listing")
      if [[ "$state" != "enabled" ]]; then
        echo "$pod: $g is '${state:-missing}', not enabled"
        rc=1
      fi
    done
    if kubectl -n kube-system logs "$pod" -c tetragon | grep -q 'failed loading policy'; then
      echo "$pod: Tetragon logged 'failed loading policy'"
      rc=1
    fi
  done
  return "$rc"
}
