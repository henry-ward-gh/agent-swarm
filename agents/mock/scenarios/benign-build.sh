#!/usr/bin/env bash
# expect: succeeded
# Ordinary agent work: write some source into the Workspace, package it, checksum it.
set -euo pipefail
mkdir -p "src-$TASK_ID"
for i in 1 2 3; do
  printf 'line %s of module %s\n' "$i" "$i" >"src-$TASK_ID/module$i.txt"
done
jq -n --arg task "$TASK_ID" '{task: $task, files: 3}' >"src-$TASK_ID/manifest.json"
tar -czf "build-$TASK_ID.tgz" "src-$TASK_ID"
sha256sum "build-$TASK_ID.tgz"
rm -rf "src-$TASK_ID" "build-$TASK_ID.tgz"
