# Guardrails are kprobe policies; egress is an allowlist of pinned ClusterIPs

Every Guardrail is a Tetragon kprobe policy (`tcp_connect`, `security_file_open`, `security_bprm_check`) using `Sigkill`, paired with `Override` where the hook allows it — never BPF LSM (`lsmhooks`), because BPF LSM is off in both the Colima VM kernel and GitHub-hosted runner kernels and can't be turned on there. The egress Guardrail is an allowlist matched on exact destination IP and port; because `tcp_connect` sees a Service's ClusterIP before kube-proxy translation, the Approved Destinations (the Swarm's Valkey, `approved-api`) are Services with pinned `spec.clusterIP` values supplied by chart values. Allowing the whole Service CIDR was rejected because the Exfil Sink is a Service too; running the Outside World outside the cluster was rejected as more moving parts in Terraform and CI.

## Consequences

- Adding an Approved Destination means pinning its ClusterIP and adding it to chart values — hostnames cannot be allowlisted.
- Guardrails are `TracingPolicyNamespaced`, rendered per Swarm by the Swarm chart from templates in `policies/`.
- If a cloud target later offers BPF LSM, LSM-based Guardrails become possible but are a new decision.
