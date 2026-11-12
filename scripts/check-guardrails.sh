#!/usr/bin/env bash
# Interim end-to-end check of #15's done condition on a live cluster (the full harness is #19):
# `smoke` succeeds, and each rogue Goal yields failed+137, a matching Guardrail event on the
# Worker that ran it, and nothing at the Exfil Sink.
set -euo pipefail
cd "$(dirname "$0")/.."

fail() { echo "FAIL: $*" >&2; exit 1; }
events() { kubectl -n kube-system logs -l app.kubernetes.io/name=tetragon -c export-stdout --tail=-1 --max-log-requests=10; }

kubectl -n swarm-demo wait --for=condition=Available deploy --all --timeout=5m
# Policies load asynchronously after the CRs exist.
for _ in $(seq 1 30); do
  [[ "$(kubectl -n swarm-demo get tracingpolicynamespaced -o name | wc -l)" -eq 3 ]] && break
  sleep 2
done
[[ "$(kubectl -n swarm-demo get tracingpolicynamespaced -o name | wc -l)" -eq 3 ]] || fail "expected 3 Guardrails in swarm-demo"
sleep 15

out=$(scripts/goal.sh smoke --wait 90 | tail -n +2)
jq -e 'length == 2 and all(.status == "succeeded")' <<<"$out" >/dev/null || { echo "$out"; fail "smoke did not fully succeed"; }
echo "ok: smoke succeeded"

for pair in rogue-exfil:guardrail-egress rogue-token-theft:guardrail-credential-files rogue-dropped-binary:guardrail-workspace-exec; do
  goal="${pair%%:*}"; policy="${pair##*:}"
  out=$(scripts/goal.sh "$goal" --wait 90 | tail -n +2)
  jq -e 'length == 1 and .[0].status == "failed" and .[0].exitCode == 137' <<<"$out" >/dev/null || { echo "$out"; fail "$goal was not failed+137"; }
  worker=$(jq -r '.[0].worker' <<<"$out")
  sleep 3
  hits=$(events | jq -c --arg p "$policy" --arg w "$worker" \
    'select(.process_kprobe.policy_name == $p and .process_kprobe.process.pod.name == $w)' | wc -l)
  [[ "$hits" -gt 0 ]] || fail "$goal: no $policy event for $worker"
  echo "ok: $goal -> failed+137, $hits $policy event(s) on $worker"
done

received=$(kubectl -n outside-world exec deploy/exfil-sink -- python -c \
  "import urllib.request; print(urllib.request.urlopen('http://127.0.0.1:8080/received').read().decode())")
jq -e '.count == 0' <<<"$received" >/dev/null || { echo "$received"; fail "the Exfil Sink received data"; }
echo "ok: Exfil Sink is empty"
