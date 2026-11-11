#!/usr/bin/env bash
# Spike: prove Tetragon Sigkill and Override inside kind on a GitHub-hosted runner.
set -uo pipefail
cd "$(dirname "$0")" || exit 1

RESULTS=()
FAILED=0
record() { RESULTS+=("$1|$2|$3"); if [ "$2" != PASS ]; then FAILED=1; fi; }
# expect <check> <wanted-exit> <actual-exit>
expect() { echo "exit=$3"; if [ "$3" -eq "$2" ]; then record "$1" PASS "exit $3"; else record "$1" FAIL "exit $3 (wanted $2)"; fi; }
section() { echo; echo "===== $* ====="; }

section "Host kernel"
uname -a
echo "lockdown: $(cat /sys/kernel/security/lockdown 2>&1)"
echo "lsm:      $(cat /sys/kernel/security/lsm 2>&1)"
grep -E 'CONFIG_BPF_KPROBE_OVERRIDE|CONFIG_FUNCTION_ERROR_INJECTION|CONFIG_BPF_LSM' "/boot/config-$(uname -r)" 2>&1

section "Create kind cluster"
kind create cluster --name spike --config kind.yaml --wait 120s || exit 1

section "Install Tetragon ${TETRAGON_VERSION}"
helm repo add cilium https://helm.cilium.io >/dev/null && helm repo update >/dev/null
helm install tetragon cilium/tetragon -n kube-system --version "${TETRAGON_VERSION}" \
  --set tetragon.hostProcPath=/procHost --wait --timeout 5m || exit 1
kubectl -n kube-system rollout status ds/tetragon --timeout=180s || exit 1

section "Tetragon startup log (features / procfs warnings)"
kubectl -n kube-system logs ds/tetragon -c tetragon | grep -iE 'feature|override|signal|procfs|hostProc|warn|error' | head -40

section "Victim pod + policies"
kubectl apply -f victim.yaml && kubectl wait --for=condition=Ready pod/victim --timeout=120s || exit 1
kubectl apply -f policies.yaml || exit 1
sleep 15
kubectl get tracingpolicies -o wide
kubectl -n kube-system logs ds/tetragon -c tetragon --since=30s | grep -iE 'error|fail|warn' | head -20
for p in spike-egress spike-credential-files spike-workspace-exec; do
  if kubectl -n kube-system logs ds/tetragon -c tetragon | grep -q "failed loading policy '$p'"; then record "load-$p" FAIL "policy rejected"; else record "load-$p" PASS "loaded"; fi
done

vexec() { kubectl exec victim -- sh -c "$1" >/tmp/out 2>&1; local rc=$?; sed 's/^/    /' /tmp/out; return $rc; }

section "1. Egress allowlist: connect to unapproved 192.0.2.10 -> expect Sigkill (137)"
vexec 'nc -w 3 192.0.2.10 80 </dev/null'; rc=$?
expect egress-sigkill 137 "$rc"

section "1b. Egress allowlist: connect to approved ClusterIP 10.96.0.1:443 -> expect success"
vexec 'nc -z -w 3 10.96.0.1 443'; rc=$?
expect egress-allowed 0 "$rc"

section "2. Credential files: read SA token -> expect Override+Sigkill (137)"
vexec 'cat /var/run/secrets/kubernetes.io/serviceaccount/token >/dev/null'; rc=$?
expect token-override-sigkill 137 "$rc"

section "2b. Override only: read /etc/passwd -> expect EPERM, process survives (exit 1)"
vexec 'cat /etc/passwd'; rc=$?
echo "exit=$rc"
if [ $rc -eq 1 ] && grep -qi 'not permitted' /tmp/out; then record override-eperm PASS "exit $rc + EPERM"; else record override-eperm FAIL "exit $rc"; fi

section "3. Workspace exec: run a binary copied into /workspace -> expect Override+Sigkill (137)"
vexec 'cp /bin/busybox /workspace/true && /workspace/true'; rc=$?
expect workspace-exec 137 "$rc"

section "3b. Benign exec outside /workspace still works"
vexec 'sha256sum /bin/busybox >/dev/null && echo ok'; rc=$?
expect benign-exec 0 "$rc"

section "Tetragon kprobe events (policy, function, action, pod, binary, args)"
sleep 5
kubectl -n kube-system logs ds/tetragon -c export-stdout > /tmp/events.json
jq -c 'select(.process_kprobe) | .process_kprobe | {policy: .policy_name, fn: .function_name, action, pod: .process.pod.name, ns: .process.pod.namespace, bin: .process.binary, args: [.args[]? | (.file_arg.path // .linux_binprm_arg.path // (.sock_arg | if . then "\(.daddr):\(.dport)" else null end))]}' /tmp/events.json | tee /tmp/kprobe-events.jsonl | head -40
for p in spike-egress spike-credential-files spike-workspace-exec; do
  n=$(jq -r "select(.policy==\"$p\" and .pod==\"victim\") | .pod" /tmp/kprobe-events.jsonl | wc -l)
  if [ "$n" -gt 0 ]; then record "events-$p-pod-metadata" PASS "$n events with pod=victim"; else record "events-$p-pod-metadata" FAIL "no events with pod=victim"; fi
done

section "SA token path as Tetragon reports it"
jq -r 'select(.policy=="spike-credential-files") | .args[]' /tmp/kprobe-events.jsonl | sort -u

section "Summary"
{
  echo "| check | result | detail |"
  echo "|---|---|---|"
  for r in "${RESULTS[@]}"; do IFS='|' read -r c s d <<<"$r"; echo "| $c | $s | $d |"; done
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
exit $FAILED
