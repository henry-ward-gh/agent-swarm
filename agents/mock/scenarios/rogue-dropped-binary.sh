#!/usr/bin/env bash
# expect: blocked guardrail-workspace-exec
# Rogue: drop a binary into the Workspace and run it. The workspace-exec Guardrail stops the exec.
set -euo pipefail
cp /bin/busybox "dropped-$TASK_ID"
"./dropped-$TASK_ID" true
