#!/usr/bin/env bash
# Submit a Goal to a Swarm and optionally wait for every Task's Result.
#
#   scripts/goal.sh <plan-name> [--wait SECONDS]
#
# Prints the Goal id; with --wait, then prints the Results as a JSON array.
# Exit: 0 = all Results in (whatever their status), 2 = timed out, 3 = Goal rejected.
#
# BROKER_CLI is the command that runs valkey-cli against the Swarm's broker.
# Default: kubectl exec into the Swarm's Valkey (SWARM_NAMESPACE, SWARM_NAME).
set -euo pipefail

name="${1:?usage: goal.sh <plan-name> [--wait SECONDS]}"
wait_s=0
if [[ "${2:-}" == "--wait" ]]; then wait_s="${3:-120}"; fi

SWARM_NAMESPACE="${SWARM_NAMESPACE:-swarm-demo}"
SWARM_NAME="${SWARM_NAME:-demo}"
read -r -a BROKER <<<"${BROKER_CLI:-kubectl -n $SWARM_NAMESPACE exec -i deploy/$SWARM_NAME-valkey -c valkey -- valkey-cli --no-auth-warning}"
vk() { "${BROKER[@]}" "$@"; }

goal_id=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen | tr '[:upper:]' '[:lower:]')
goal=$(jq -cn --arg id "$goal_id" --arg name "$name" '{version: 1, id: $id, name: $name}')
vk LPUSH goals "$goal" >/dev/null
echo "$goal_id"
[[ "$wait_s" -gt 0 ]] || exit 0

deadline=$((SECONDS + wait_s))
task_ids=()
while [[ $SECONDS -lt $deadline ]]; do
  err=$(vk GET "goal:$goal_id:error")
  if [[ -n "$err" ]]; then echo "goal rejected: $err" >&2; exit 3; fi
  # The count is written after the last Task is queued; reading the list earlier can miss Tasks.
  count=$(vk GET "goal:$goal_id:count")
  if [[ -n "$count" ]]; then
    mapfile -t task_ids < <(vk LRANGE "goal:$goal_id:tasks" 0 -1 | sed '/^$/d')
    [[ ${#task_ids[@]} -eq "$count" ]] && break
  fi
  sleep 1
done
# A plan with no Scenarios splits into zero Tasks: nothing to wait for.
if [[ "${count:-}" == "0" ]]; then echo "[]"; exit 0; fi

while [[ $SECONDS -lt $deadline ]]; do
  results=()
  for t in "${task_ids[@]}"; do
    r=$(vk GET "result:$t")
    [[ -n "$r" ]] && results+=("$r")
  done
  if [[ ${#task_ids[@]} -gt 0 && ${#results[@]} -eq ${#task_ids[@]} ]]; then
    printf '%s\n' "${results[@]}" | jq -s .
    exit 0
  fi
  sleep 1
done
echo "timed out after ${wait_s}s waiting for goal $goal_id" >&2
exit 2
