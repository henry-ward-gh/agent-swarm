#!/usr/bin/env bash
# Interim end-to-end check of #15's done condition on a live cluster (the full harness is #19):
# `smoke` succeeds, and each rogue Goal yields failed+137, a matching Guardrail event on the
# Worker that ran it, and nothing at the Exfil Sink.
set -euo pipefail
cd "$(dirname "$0")/.."

SWARM_NAMESPACE="${SWARM_NAMESPACE:-swarm-demo}"
fail() { echo "FAIL: $*" >&2; exit 1; }
events() { kubectl -n kube-system logs -l app.kubernetes.io/name=tetragon -c export-stdout --tail=-1 --max-log-requests=10; }

kubectl -n "$SWARM_NAMESPACE" wait --for=condition=Available deploy --all --timeout=5m
# Policies load asynchronously after the CRs exist.
for _ in $(seq 1 30); do
  [[ "$(kubectl -n "$SWARM_NAMESPACE" get tracingpolicynamespaced -o name | wc -l)" -eq 3 ]] && break
  sleep 2
done
[[ "$(kubectl -n "$SWARM_NAMESPACE" get tracingpolicynamespaced -o name | wc -l)" -eq 3 ]] || fail "expected 3 Guardrails in $SWARM_NAMESPACE"
sleep 15

out=$(scripts/goal.sh smoke --wait 90 | tail -n +2)
jq -e 'length == 2 and all(.status == "succeeded")' <<<"$out" >/dev/null || { echo "$out"; fail "smoke did not fully succeed"; }
echo "ok: smoke succeeded"

for pair in rogue-exfil:guardrail-egress rogue-token-theft:guardrail-credential-files rogue-dropped-binary:guardrail-workspace-exec; do
  goal="${pair%%:*}"; policy="${pair##*:}"
  out=$(scripts/goal.sh "$goal" --wait 90 | tail -n +2)
  jq -e 'length == 1 and .[0].status == "failed" and .[0].exitCode == 137' <<<"$out" >/dev/null || { echo "$out"; fail "$goal was not failed+137"; }
  worker=$(jq -r '.[0].worker' <<<"$out")
  started=$(jq -r '.[0].startedAt' <<<"$out"); finished=$(jq -r '.[0].finishedAt' <<<"$out")
  sleep 3
  # Only this Task's run counts: that Worker, in this namespace, inside the Task's window, with an
  # enforcing action from the expected policy. (A timeout also exits 137, and old events linger.)
  hits=$(events | jq -c --arg p "$policy" --arg w "$worker" --arg ns "$SWARM_NAMESPACE" --arg s "$started" --arg f "$finished" '
    def secs: sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601;
    select(.process_kprobe.policy_name == $p
      and .process_kprobe.process.pod.namespace == $ns
      and .process_kprobe.process.pod.name == $w
      and (.process_kprobe.action | IN("KPROBE_ACTION_SIGKILL", "KPROBE_ACTION_OVERRIDE"))
      and (.time | secs) >= ($s | secs) and (.time | secs) <= (($f | secs) + 1))' | wc -l)
  [[ "$hits" -gt 0 ]] || fail "$goal: no $policy event for $worker"
  echo "ok: $goal -> failed+137, $hits $policy event(s) on $worker"
done

received=$(kubectl -n outside-world exec deploy/exfil-sink -- python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/received').read().decode())")
jq -e '.count == 0' <<<"$received" >/dev/null || { echo "$received"; fail "the Exfil Sink received data"; }
echo "ok: Exfil Sink is empty"
