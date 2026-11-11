# Terraform applies in two stages and never creates in-cluster secrets

Each environment root is split into two stages applied in sequence — `envs/<env>/cluster` (creates the cluster, outputs a cluster-agnostic `kubernetes` connection object) then `envs/<env>/bootstrap` (reads it via `terraform_remote_state` and helm-installs Argo CD plus the root app-of-apps). We split from day one rather than using one apply because HashiCorp warns that configuring a provider from a cluster created in the same apply is unreliable, and a showcase whose selling point is CI cannot afford flaky applies; cloud environments need the same split anyway.

Terraform stops at the platform. In-cluster secrets such as each Swarm's broker password are produced inside the cluster by a GitOps-deployed secret-generator controller from annotated Secrets in Git — not by Terraform (which would then need to know which Swarms exist) and not committed as fixed values.

## Consequences

- `task up` runs two applies; `task down` deletes the kind cluster and its local state rather than running `destroy` on the bootstrap stage.
- PR CI can `plan` only the cluster stage; the bootstrap stage is exercised by the e2e job's real apply.
- A secret-generator controller is part of the platform Argo CD deploys.
