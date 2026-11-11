# Can Tetragon enforce inside kind on GitHub-hosted runners?

Research for [#3](https://github.com/henry-ward-gh/agent-swarm/issues/3). Sources checked 2026-11-11.

## Answer

**Yes, very likely, with caveats.** GitHub-hosted x64 Ubuntu runners are full Azure VMs with root, Docker and kind preinstalled. Their kernel (7.0 `-azure`) is built with every option Tetragon needs for observing events and for both enforcement actions. That includes `CONFIG_BPF_KPROBE_OVERRIDE=y`, which `Override` needs. Tetragon's own CI runs its full kind e2e suite on these runners. It also runs its in-process `Sigkill`/`Override` unit tests on them, as root on the host. Because kind nodes share the runner's kernel, enforcement inside kind should behave the same.

Three things to plan around:

1. **No BPF LSM.** `CONFIG_BPF_LSM=y`, but `bpf` is not in the boot-time LSM list, and you can't change the kernel command line on hosted runners. So **`lsmhooks` policies will not load**. Use kprobes (`Sigkill` + `Override`) instead.
2. **Avoid `syscalls` tracepoints that read user memory.** They are flaky on the current runner kernel (Ubuntu kernel bug), and Tetragon skips those tests in its own CI.
3. **kind needs host `/proc` mounted in.** Otherwise pod attribution silently breaks.

**Not verified empirically.** Nobody has published a run of a `Sigkill`/`Override` TracingPolicy enforcing a pod *inside kind* on a hosted runner. Tetragon's kind e2e suite only exercises observation. Its enforcement tests skip themselves silently when a BPF helper is missing, and the CI logs aren't verbose enough to prove they ran (see [Residual risk](#residual-risk)).

## Runner kernel and config

| Label | OS | Kernel (image 2026-11-01) |
|---|---|---|
| `ubuntu-latest` / `ubuntu-24.04` | 24.04.5 LTS | `7.0.0-1017-azure` |
| `ubuntu-26.04` | 26.04.1 LTS | `7.0.0-1019-azure` |

- `ubuntu-latest` still maps to `ubuntu-24.04`. Source: [runner-images README](https://github.com/actions/runner-images/blob/main/README.md), [Ubuntu2404-Readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md), [Ubuntu2604-Readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2604-Readme.md).
- The kernel was confirmed live as `Linux runnervm… 7.0.0-1017-azure #17~24.04.1-Ubuntu` in Tetragon's [gotests run 43001921119](https://github.com/cilium/tetragon/actions/runs/43001921119) (`build (ubuntu-24.04)` job).
- The 24.04 image ships Docker 28.0.4, Kind 0.33.0, Kubectl 1.37.2 and Helm 3.22.1. The 26.04 image ships Helm 4.3.1 and Docker 29.4.2 ([Ubuntu2404-Readme](https://github.com/actions/runner-images/blob/main/images/ubuntu/Ubuntu2404-Readme.md)).

Kernel config: I read `.config` from Ubuntu's own package, [`linux-headers-7.0.0-1017-azure_7.0.0-1017.17~24.04.1_amd64.deb`](https://archive.ubuntu.com/ubuntu/pool/main/l/linux-azure-7.0/) (noble-updates). It matches the running runner kernel exactly.

```
CONFIG_BPF_SYSCALL=y           CONFIG_BPF_JIT=y           CONFIG_BPF_EVENTS=y
CONFIG_DEBUG_INFO_BTF=y        CONFIG_KPROBES=y           CONFIG_FPROBE=y
CONFIG_BPF_KPROBE_OVERRIDE=y   CONFIG_FUNCTION_ERROR_INJECTION=y
CONFIG_CGROUP_BPF=y            CONFIG_SECURITY_PATH=y
CONFIG_BPF_LSM=y               CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor"   # no "bpf"
CONFIG_SECURITY_LOCKDOWN_LSM=y
```

Here is how that maps to Tetragon's requirements:

- **`Sigkill`** uses `bpf_send_signal` (kernel 5.3+). Available.
- **`Override` on kprobes** "is only available on kernels compiled with `CONFIG_BPF_KPROBE_OVERRIDE`". It works on syscalls, on `ALLOW_ERROR_INJECTION()` functions, and on `security_*` hooks from 5.7 onward ([selectors.md, Override action](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/concepts/tracing-policy/selectors.md#override-action)). Available.
- **`lsmhooks`** needs `bpf` listed in `/sys/kernel/security/lsm`. The docs' only remedy is a GRUB `lsm=` change plus a reboot ([hooks.md, LSM BPF](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/concepts/tracing-policy/hooks.md#lsm-bpf)), which isn't possible on an ephemeral hosted runner. **Not available.**
- The general Tetragon config checklist is in [installation FAQ](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/installation/faq.md).

## Prior art: Tetragon's own CI

- **[`run-e2e-tests.yaml`](https://github.com/cilium/tetragon/blob/main/.github/workflows/run-e2e-tests.yaml)** runs the full Helm-installed Tetragon in **kind on GitHub-hosted runners**. The matrix is `ubuntu-22.04` and `ubuntu-22.04-arm64`. Each e2e package runs in its own job with `timeout-minutes: 20`. Setup uses `helm/kind-action` with `install_only: true` and kind v0.33.0, and the test harness creates the cluster. Images are pulled once and loaded into kind.
- **kind config used by that suite** ([`tests/e2e/helpers/cluster.go`](https://github.com/cilium/tetragon/blob/main/tests/e2e/helpers/cluster.go)), node image `kindest/node:v1.37.0`:
  ```yaml
  nodes:
  - role: control-plane
    extraMounts:
    - hostPath: "/proc"
      containerPath: "/procRoot"
    - hostPath: "/tetragonExport"
      containerPath: "/tetragonExport"
    - hostPath: "/sys/fs/bpf"
      containerPath: "/sys/fs/bpf"
      propagation: Bidirectional
  ```
  The simpler upstream local recipe ([`contrib/kind/kind-config.yaml`](https://github.com/cilium/tetragon/blob/main/contrib/kind/kind-config.yaml) + [`values.yaml`](https://github.com/cilium/tetragon/blob/main/contrib/kind/values.yaml)) mounts `/proc` at `/procHost` and sets `tetragon.hostProcPath: /procHost`.
- **What the kind e2e suite covers:** `skeleton`, `labels`, `policyfilter`, `nodeselector`, `grpctls`, `rthooks` and `policytest`. `policytest` is pinned to `kprobe-lseek` and `tracepoint-exec` ([policytest_test.go](https://github.com/cilium/tetragon/blob/main/tests/e2e/tests/policytest/policytest_test.go)). **None of them exercises `Sigkill` or `Override` inside kind.** Pod-scoped filtering (`policyfilter`, `labels`) is covered, so pod attribution in kind on runners is proven.
- **[`gotests.yml`](https://github.com/cilium/tetragon/blob/main/.github/workflows/gotests.yml)** runs `make test` with `sudo -E` directly on `ubuntu-24.04`, `ubuntu-24.04-arm64` and `ubuntu-26.04` (26.04 skips the full suite because of [cilium/tetragon#3583](https://github.com/cilium/tetragon/issues/3583) path differences). That suite includes [`enforcer_test.go`](https://github.com/cilium/tetragon/blob/main/pkg/sensors/tracing/enforcer_test.go) and `kprobe_sigkill_test.go`. Those tests call `t.Skip` when `bpf.HasOverrideHelper()`, `HasModifyReturn()` or `HasSignalHelper()` are false, and the job runs without `-v`, so the logs don't show whether they ran or skipped.
- **[`vmtests.yml`](https://github.com/cilium/tetragon/blob/main/.github/workflows/vmtests.yml)** boots many kernels in nested VMs (little-vm-helper) on `ubuntu-latest`. This is heavier prior art if we ever need a kernel with BPF LSM in CI.
- **The chart works unprivileged.** Tetragon chart v1.8.0 defaults to `privileged: false` with capabilities `SYS_ADMIN, SYS_PTRACE, SYS_RESOURCE, DAC_OVERRIDE, SYSLOG`, AppArmor `Unconfined` and `hostNetwork: true` ([chart values](https://github.com/cilium/tetragon/blob/main/install/kubernetes/tetragon/values.yaml)). kind node containers are privileged anyway, so this works as-is.

## Known issues

- **[cilium/tetragon#5846](https://github.com/cilium/tetragon/issues/5846)** (open): on the GitHub runner kernel, BPF on `syscalls` tracepoints that read user memory (`sys_enter_write`, `sys_enter_mkdirat`, `char_buf` args) only fires on the CPU of the attaching perf event. The `tracepoint-exec` policytest is flaky on runners but fine in VMs. Upstream attributes this to an Ubuntu kernel bug and skips `TestCharBufTracepoint|TestGenericTracepointMeta|TestStringTracepoint` in CI ([PR #5856](https://github.com/cilium/tetragon/pull/5856), [PR #5894](https://github.com/cilium/tetragon/pull/5894)). **Implication:** CI observation assertions should hook kprobes (e.g. `sys_write` with `syscall: true`, `security_file_open`, `tcp_connect`), not `syscalls/*` tracepoints.
- **[cilium/tetragon#4883](https://github.com/cilium/tetragon/issues/4883)** (open): if Tetragon's procfs isn't the host's (the inode check on `/proc/1/ns/pid` fails), it only *warns*. Every `process_kprobe` event from pods then arrives with empty `binary`/`pod`, which silently neutralises pod-scoped policies. The issue was reported against Docker Desktop LinuxKit kind on Apple Silicon (our local macOS setup), but the same thing happens anywhere the kind `/proc` extraMount + `hostProcPath` is missing. **Mitigation:** always mount host `/proc` and set `hostProcPath`. Assert that the warning is absent, and assert that events carry `pod` metadata.
- **[cilium/tetragon#5869](https://github.com/cilium/tetragon/issues/5869)**, [#5113](https://github.com/cilium/tetragon/issues/5113) (closed): earlier arm64-runner-specific failures. Prefer x64 runners.

## Limits to plan around

| Topic | Hosted runner reality | Plan |
|---|---|---|
| Privileged containers | Allowed. Runner is a VM with passwordless sudo, kind node is privileged | No action |
| BPF fs | Host has `/sys/fs/bpf`. Mounting it into the kind node (`Bidirectional`) keeps pinned maps across Tetragon restarts | Copy Tetragon's e2e kind config |
| Host `/proc` | Not visible to Tetragon unless mounted into the node | extraMount `/proc` → `/procHost` (or `/procRoot`) + `tetragon.hostProcPath` |
| `Sigkill` | Supported by kernel | Use |
| `Override` (kprobe / `security_*` / syscalls) | `CONFIG_BPF_KPROBE_OVERRIDE=y` | Use for x64. On arm64, kprobe override support is uncertain, so avoid arm runners |
| `lsmhooks` | BPF LSM not active, can't reboot | Don't use in CI-tested Guardrails |
| `syscalls/*` tracepoints with user-memory args | Flaky (#5846) | Use kprobes instead |
| Kernel drift | `-azure` kernel bumps with weekly image updates | Log `uname -r` and Tetragon's detected-features line in every CI run |

## Residual risk

1. **No direct proof of `Override`/`Sigkill` inside kind on a hosted runner.** Upstream only proves observation in kind, and its host-level enforcement tests could be silently skipping. The kernel config makes it very likely they work.
2. **Kernel lockdown.** `CONFIG_SECURITY_LOCKDOWN_LSM=y`, and I didn't find whether hosted runner VMs boot with Secure Boot. Lockdown in `integrity` mode is not documented to block `bpf_override_return`, but I didn't verify that.

Both are cheap to settle in the first CI ticket. Add a step that prints `uname -r`, `cat /sys/kernel/security/lockdown /sys/kernel/security/lsm` and Tetragon's startup BPF feature detection output (the [FAQ](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/installation/faq.md) shows the `override_return: true` form). Then apply one `Sigkill` and one `Override` TracingPolicy against a rogue pod and assert the outcome: exit 137, or `EPERM` from the blocked call.
