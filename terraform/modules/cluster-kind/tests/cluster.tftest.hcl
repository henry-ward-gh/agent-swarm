mock_provider "kind" {
  mock_resource "kind_cluster" {
    defaults = {
      endpoint               = "https://127.0.0.1:6443"
      cluster_ca_certificate = "test-ca"
      client_certificate     = "test-cert"
      client_key             = "test-key"
      kubeconfig_path        = "/tmp/test-kubeconfig"
      context_name           = "kind-agent-swarm"
    }
  }
}

run "one_control_plane_and_one_worker_by_default" {
  command = plan

  assert {
    condition     = [for n in kind_cluster.this.kind_config[0].node : n.role] == ["control-plane", "worker"]
    error_message = "Expected exactly one control-plane and one worker node."
  }
}

run "worker_count_is_configurable" {
  command = plan

  variables {
    workers = 3
  }

  assert {
    condition     = length(kind_cluster.this.kind_config[0].node) == 4
    error_message = "Expected 1 control-plane + 3 workers."
  }
}

run "every_node_gives_tetragon_host_proc_and_bpffs" {
  command = plan

  variables {
    workers = 2
  }

  assert {
    condition = alltrue([
      for n in kind_cluster.this.kind_config[0].node : anytrue([
        for m in n.extra_mounts : m.host_path == "/proc" && m.container_path == "/procHost"
      ])
    ])
    error_message = "Every node must mount host /proc at /procHost (Tetragon hostProcPath)."
  }

  assert {
    condition = alltrue([
      for n in kind_cluster.this.kind_config[0].node : anytrue([
        for m in n.extra_mounts : m.host_path == "/sys/fs/bpf" && m.container_path == "/sys/fs/bpf" && m.propagation == "Bidirectional"
      ])
    ])
    error_message = "Every node must mount /sys/fs/bpf with Bidirectional propagation."
  }
}

run "rejects_negative_worker_count" {
  command = plan

  variables {
    workers = -1
  }

  expect_failures = [var.workers]
}

run "exposes_the_cluster_agnostic_kubernetes_contract" {
  command = apply

  assert {
    condition = output.kubernetes == {
      host                   = "https://127.0.0.1:6443"
      cluster_ca_certificate = "test-ca"
      client_certificate     = "test-cert"
      client_key             = "test-key"
      token                  = null
      exec                   = null
    }
    error_message = "kubernetes output must carry host/CA/cert/key with null token and exec."
  }

  assert {
    condition     = output.kubeconfig_path == "/tmp/test-kubeconfig" && output.context_name == "kind-agent-swarm"
    error_message = "kubeconfig_path and context_name must be exposed for kubectl users."
  }
}
