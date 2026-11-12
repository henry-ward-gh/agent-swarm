#!/usr/bin/env bash
# The Swarm chart must refuse to render Guardrails that would be wrong (ADR 0003).
set -euo pipefail
cd "$(dirname "$0")/.."

must_fail() { # <why> <helm set args...>
  local why="$1"; shift
  if helm template x agents/charts/swarm --set guardrails.enabled=true "$@" >/dev/null 2>&1; then
    echo "render accepted: $why" >&2
    exit 1
  fi
  echo "ok: render rejects $why"
}

must_fail "a pinned broker IP outside the Service CIDR" --set broker.clusterIP=192.0.2.1
must_fail "an egress IP outside the Service CIDR" --set broker.clusterIP=10.96.0.110 --set 'worker.egress.allow={10.200.0.1:80}'
must_fail "Guardrails without a pinned broker IP"
