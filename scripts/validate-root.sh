#!/usr/bin/env bash
# Render gitops/root and validate it, including Argo CD Application CRs
# (schemas from the datree CRDs catalog, pinned to a commit so lint is reproducible). Extra args are passed to `helm template`.
set -euo pipefail
cd "$(dirname "$0")/.."
helm template root gitops/root -n argocd "$@" | kubeconform -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/89c736bdde38b5fecd0f8436ec5f3aa3679a3b86/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
