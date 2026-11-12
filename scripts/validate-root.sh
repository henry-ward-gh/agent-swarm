#!/usr/bin/env bash
# Render gitops/root and validate it, including Argo CD Application CRs
# (schemas from the datree CRDs catalog). Extra args are passed to `helm template`.
set -euo pipefail
cd "$(dirname "$0")/.."
helm template root gitops/root -n argocd "$@" | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
