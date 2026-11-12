# A kind cluster ready for Tetragon: every node sees the host's /proc (so events
# carry pod metadata, cilium/tetragon#4883) and shares the BPF filesystem.
locals {
  nodes = concat(["control-plane"], [for _ in range(var.workers) : "worker"])
}

resource "kind_cluster" "this" {
  name            = var.name
  node_image      = var.node_image
  kubeconfig_path = var.kubeconfig_path
  wait_for_ready  = true

  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"

    dynamic "node" {
      for_each = local.nodes

      content {
        role = node.value

        extra_mounts {
          host_path      = "/proc"
          container_path = "/procHost"
        }

        extra_mounts {
          host_path      = "/sys/fs/bpf"
          container_path = "/sys/fs/bpf"
          propagation    = "Bidirectional"
        }
      }
    }
  }
}
