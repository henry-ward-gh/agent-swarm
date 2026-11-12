#!/usr/bin/env bash
# Validate the observability chart: rendered manifests (incl. the ServiceMonitor CRD kind, schemas from the
# datree CRDs catalog pinned to a commit), the dashboard JSON, and the Alloy config (with Alloy's own parser).
set -euo pipefail
cd "$(dirname "$0")/.."
ALLOY_IMAGE="${ALLOY_IMAGE:-grafana/alloy:v1.21.3}" # Alloy chart 1.15.0's appVersion

helm template observability gitops/platform/observability -n monitoring | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/89c736bdde38b5fecd0f8436ec5f3aa3679a3b86/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

jq -e '.uid == "swarm-activity" and (.panels | length) > 0' gitops/platform/observability/files/swarm-activity.json >/dev/null

if command -v docker >/dev/null; then
  docker run --rm -e NODE_NAME=node -e LOKI_URL=http://loki:3100 \
    -v "$PWD/gitops/platform/observability/files/config.alloy:/config.alloy:ro" "$ALLOY_IMAGE" validate /config.alloy
  echo "alloy config: valid"
else
  echo "docker not found: skipping the Alloy config check" >&2
fi
