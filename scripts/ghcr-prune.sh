#!/usr/bin/env bash
# Retention for the Mock Agent image on GHCR: keep the newest N package versions, delete the rest,
# never a version tagged `main` or `latest`. Cosign signatures are versions too, so N counts them:
# N=60 keeps roughly the last 30 images with their signatures.
#
#   scripts/ghcr-prune.sh <owner> <package> <keep> [--dry-run]
#
# <package> is the name as GHCR lists it, e.g. agent-swarm/mock-agent. Needs `gh` and packages:write.
set -euo pipefail

# select_prunable <keep> — reads the versions JSON array on stdin, prints the ids to delete (newest first).
select_prunable() {
  local keep="$1"
  [[ "$keep" =~ ^[0-9]+$ ]] || { echo "keep must be a number, got '$keep'" >&2; return 1; }
  jq -r --argjson keep "$keep" '
    sort_by(.created_at) | reverse
    | .[$keep:]
    | map(select((.metadata.container.tags // []) | any(. == "main" or . == "latest") | not))
    | .[].id'
}

main() {
  local owner="${1:?usage: ghcr-prune.sh <owner> <package> <keep> [--dry-run]}" package="${2:?package}" keep="${3:?keep}"
  local dry=false base type versions ids id out
  [[ "${4:-}" == "--dry-run" ]] && dry=true

  type=$(gh api "users/$owner" -q .type)
  if [[ "$type" == "Organization" ]]; then base="orgs/$owner"; else base="users/$owner"; fi
  base="$base/packages/container/${package//\//%2F}"

  versions=$(gh api --paginate "$base/versions?per_page=100" | jq -s 'add // []')
  ids=$(select_prunable "$keep" <<<"$versions")
  if [[ -z "$ids" ]]; then
    echo "nothing to prune ($(jq length <<<"$versions") versions, keeping $keep)"
    return 0
  fi
  for id in $ids; do
    if $dry; then
      echo "would delete version $id"
    else
      echo "deleting version $id"
      # Concurrent publishes can prune the same versions: already gone is fine, anything else is not.
      if ! out=$(gh api -X DELETE "$base/versions/$id" 2>&1); then
        if [[ "$out" == *"404"* ]]; then
          echo "version $id already gone"
        else
          echo "$out" >&2
          return 1
        fi
      fi
    fi
  done
}

# Run only when executed, so the tests can source select_prunable.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
