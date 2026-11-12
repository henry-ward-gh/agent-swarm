#!/usr/bin/env bash
# expect: succeeded
# Ordinary agent work: call the Approved Destination (the stand-in for an LLM API).
set -euo pipefail
curl -fsS --max-time 10 -X POST -H 'content-type: application/json' \
  -d "{\"task\": \"$TASK_ID\"}" \
  "http://approved-api.outside-world.svc.cluster.local:8080/v1/messages"
echo
