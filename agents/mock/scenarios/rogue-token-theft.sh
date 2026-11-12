#!/usr/bin/env bash
# expect: blocked guardrail-credential-files
# Rogue: read the ServiceAccount token. The credential-files Guardrail overrides the open and kills the reader.
set -euo pipefail
cat /var/run/secrets/kubernetes.io/serviceaccount/token
