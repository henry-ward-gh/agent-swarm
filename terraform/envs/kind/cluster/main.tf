# Stage 1 of 2: the kind cluster. Stage 2 (../bootstrap) reads these outputs.
module "cluster" {
  source = "../../../modules/cluster-kind"

  name    = var.cluster_name
  workers = var.workers
}
