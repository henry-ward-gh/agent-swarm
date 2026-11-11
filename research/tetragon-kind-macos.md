# Can Tetragon observe and enforce under kind on macOS?

Research for issue #2. Researched 2026-11-11 against Tetragon `main`
(commit `63332a1c`), Docker Desktop, OrbStack and Colima/Lima primary
sources. **Nothing here was tested on a Mac.** Each claim is marked
**confirmed** (read in source, docs or the shipped kernel config) or
**unverified** (inferred, or reported by a third party). The
[verification checklist](#verification-checklist-run-once-on-a-mac) lists
the commands that settle the open points in about 5 minutes.

## TL;DR

| | Docker Desktop | OrbStack | **Colima (recommended)** |
|---|---|---|---|
| VM kernel | Docker's own LinuxKit-derived build (closed config) | OrbStack's own build (closed config) | Stock Ubuntu 24.04 `6.8.0-*-generic` |
| BTF (`/sys/kernel/btf/vmlinux`) | Yes since DD 4.25 / kernel 6.4.16 — confirmed | Yes in practice — unverified, inferred from users running Tetragon | Yes, `CONFIG_DEBUG_INFO_BTF=y` — confirmed |
| kprobe / tracepoint policies load | Yes — third-party report (6.12.5-linuxkit) | Yes — third-party reports (6.9, 6.12, 6.17) | Yes — confirmed by config |
| `Sigkill` / `Signal` | Probably — unverified | Probably — unverified | Yes — confirmed by config (`bpf_send_signal`, kernel ≥ 5.3) |
| `Override` on syscalls (`CONFIG_BPF_KPROBE_OVERRIDE`) | **Unknown.** Upstream LinuxKit config has it *off*, and DD's own config is not published | **Unknown.** Config not published | **Yes**, `=y` on arm64 and amd64 — confirmed |
| `Override` on `security_*` kprobes (fmod_ret) | Unknown | Unknown | Yes on 6.8 — inferred from Tetragon source |
| `lsmhooks` (BPF LSM) | No: upstream LinuxKit has `CONFIG_BPF_LSM` unset | Probably yes: `bpf` is in the LSM list on 6.17.8 | Built in, but **`bpf` is not in the default `CONFIG_LSM`**, so it needs a boot argument |
| Pod attribution under kind | **Broken by default.** Documented silent failure (Tetragon #4883) | Same risk (inode-mismatch warning seen, #2257) | Same risk unless `/proc` from the VM is mounted. The documented fix should work because Docker runs inside the Lima VM (unverified) |

**Recommendation: document Colima for local dev.** It is the only one of
the three whose kernel config is public and stock. That config has every
option Tetragon lists as needed, `CONFIG_BPF_KPROBE_OVERRIDE` included, on
both Apple Silicon and Intel. It is also the setup Tetragon's maintainers
point to: the FAQ recommends "a recent Linux distribution" in a
Lima/UTM VM, and Colima is a Lima wrapper. Docker Desktop and OrbStack
both ship closed, custom kernels, and Tetragon maintainers have called
both unsupported or unknown.

## Background: what each Tetragon feature needs

- **Minimum kernel and BTF.** Kernel ≥ 4.19, but arm64 needs ≥ 5.10 for
  full functionality. BTF must be present at `/sys/kernel/btf/vmlinux`
  for CO-RE. The FAQ lists the needed kernel options, including
  `CONFIG_DEBUG_INFO_BTF`, `CONFIG_BPF_KPROBE_OVERRIDE` ("Enforcement"),
  `CONFIG_AUDIT` and `CONFIG_CGROUP_BPF`.
  Source: [`docs/.../installation/faq.md`](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/installation/faq.md)
  ([rendered](https://tetragon.io/docs/installation/faq/)).
- **`Sigkill` / `Signal`.** These use the `bpf_send_signal` helper, which
  Tetragon probes with `HasSignalHelper()`
  ([`pkg/bpf/detect_linux.go`](https://github.com/cilium/tetragon/blob/main/pkg/bpf/detect_linux.go)).
  No special kernel option is needed beyond kprobes and BPF events.
  `SIGKILL` stops the process synchronously but does **not** guarantee the
  operation itself is prevented. For example, a `write()` may still land.
  The docs say to combine it with `Override` when the operation must not
  complete ([`concepts/enforcement/_index.md`](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/concepts/enforcement/_index.md)).
- **`Override`.** There are two code paths, and Tetragon picks one based on
  the hook ([`validateOverride` in `pkg/sensors/tracing/generickprobe.go`](https://github.com/cilium/tetragon/blob/main/pkg/sensors/tracing/generickprobe.go)):
  - Syscalls (`syscall: true`) need the `bpf_override_return` helper,
    which means **`CONFIG_BPF_KPROBE_OVERRIDE`**. Without it the policy is
    rejected with `override action not supported on syscalls,
    bpf_override_return helper not available`.
  - `security_*` kernel functions use **fmod_ret** (BPF trampolines,
    probed by attaching to `security_task_prctl`). This path does *not*
    need `CONFIG_BPF_KPROBE_OVERRIDE`. Trampolines on arm64 need roughly
    kernel ≥ 6.0.
  - Any other function is rejected: `override action can be used only
    with syscalls and security_ hooks`.
  - The docs confirm `Override` "is only available on kernels compiled
    with `CONFIG_BPF_KPROBE_OVERRIDE`" for the kprobe case
    ([`tracing-policy/selectors.md#override-action`](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/concepts/tracing-policy/selectors.md)).
- **`lsmhooks`.** These need `CONFIG_BPF_LSM=y` **and** `bpf` listed in
  `/sys/kernel/security/lsm`
  ([`tracing-policy/hooks.md#lsm-bpf`](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/concepts/tracing-policy/hooks.md)).
- **kind specifically.** Tetragon needs the *host* procfs. Tetragon's
  kind instructions mount `/proc` into the node as `/procHost` and set
  `tetragon.hostProcPath=/procHost`. The instructions say this is "when
  using a Linux system"
  ([`getting-started/install-k8s.md`](https://github.com/cilium/tetragon/blob/main/docs/content/en/docs/getting-started/install-k8s.md)).

## Per runtime

### Docker Desktop

- **BTF: yes on recent versions (confirmed).** The Tetragon FAQ says DD
  24.0.6 with kernel `6.4.16-linuxkit` or newer is needed. Older DD
  kernels lacked BTF ([docker/for-mac#6800](https://github.com/docker/for-mac/issues/6800)).
- **The kernel config is Docker's own and not published.** A Docker
  engineer said in April 2024: "Docker Desktop uses its own kernel config,
  now. It's not using the Linuxkit config anymore"
  ([docker/for-mac#7250](https://github.com/docker/for-mac/issues/7250)).
  The same thread shows DD once shipped with `CONFIG_SECURITY` off. That
  broke Tetragon's base sensor until DD 4.30 re-enabled it.
- **Upstream LinuxKit configs (a proxy only).** `kernel/6.12.x` and
  `kernel/6.18.x` (`config-aarch64` and `config-x86_64`) contain
  `# CONFIG_BPF_KPROBE_OVERRIDE is not set` and
  `# CONFIG_BPF_LSM is not set`, with
  `CONFIG_LSM="yama,loadpin,safesetid,integrity,apparmor"`
  ([linuxkit/linuxkit kernel/6.12.x/config-aarch64](https://github.com/linuxkit/linuxkit/blob/master/kernel/6.12.x/config-aarch64)).
  Whether DD's kernel matches this for override is **unverified**. Treat
  syscall `Override` on DD as "probably not".
- **Kprobes load, but pod attribution silently breaks (third-party
  report).** [cilium/tetragon#4883](https://github.com/cilium/tetragon/issues/4883)
  (Apr 2026) covers Tetragon 1.6.1 on kind on DD with
  `6.12.5-linuxkit aarch64`. Tetragon starts and kprobe policies attach
  and fire. However, the procfs check logs `inode mismatch: procfs does not
  appear to be host procfs`, only 39 of 95 processes are seeded into
  `execve_map`, and **every `process_kprobe` event from user pods has
  empty `binary`/`pod`/`exec_id`**. Pod-scoped policies therefore match
  nothing, while Tetragon still looks healthy. A Tetragon maintainer
  replied that the DD kernel "might not be supported by tetragon as it
  lacks some kernel configs needed".
- **The `/procHost` fix on DD is uncertain.** kind's docs say that on
  Docker for Mac an `extraMounts.hostPath` must be in DD's file-sharing
  list ([kind configuration docs](https://github.com/kubernetes-sigs/kind/blob/main/site/content/docs/user/configuration.md#extra-mounts)).
  DD's docs say paths outside the shared list give `Mounts denied`, and
  they say nothing about VM paths such as `/proc`
  ([DD settings: file sharing](https://docs.docker.com/desktop/settings-and-maintenance/settings/)).
  It is **unverified** whether `hostPath: /proc` reaches the VM's procfs
  on DD.

### OrbStack

- **The kernel is OrbStack's own build** (`6.x.y-orbstack-…`). There is
  no public config. An OrbStack staff member noted that `/proc/config.gz`
  did not list kprobes even though they were enabled
  ([orbstack#761](https://github.com/orbstack/orbstack/issues/761)), so
  even the in-VM config may not be authoritative.
- **Users run Tetragon on it:** kind or k3s on kernels 6.9.3, 6.12.10 and
  6.17.8, with policies loading
  ([tetragon#2597](https://github.com/cilium/tetragon/issues/2597),
  [#3369](https://github.com/cilium/tetragon/issues/3369),
  [#4839](https://github.com/cilium/tetragon/issues/4839)). The
  6.17.8-orbstack dmesg in #4839 shows
  `LSM: initializing lsm=capability,landlock,yama,bpf`, so **BPF LSM looks
  active**.
- **History of gaps.** In 2024, Tetragon on kind on OrbStack
  (`6.4.16-orbstack`) failed BTF module iteration and detected
  `override_return: false … fmodret: false … signal: false`. A maintainer
  advised using "a more usual distro … like Debian or Ubuntu"
  ([tetragon#2257](https://github.com/cilium/tetragon/issues/2257)).
  `CONFIG_AUDIT`, which Tetragon lists as required, was only added in
  OrbStack v2.2.4 in October 2026
  ([orbstack#2724](https://github.com/orbstack/orbstack/issues/2724)).
  OrbStack has also added options on request, such as
  `CONFIG_BSD_PROCESS_ACCT` for Tetragon in
  [orbstack#854](https://github.com/orbstack/orbstack/issues/854).
- **`CONFIG_BPF_KPROBE_OVERRIDE`: unknown.** No public source either way.

### Colima (Lima) — recommended

- **The VM image is stock Ubuntu.** Colima ≥ 0.6 "uses Ubuntu as the
  underlying image"
  ([colima FAQ](https://github.com/abiosoft/colima/blob/main/docs/FAQ.md)).
  The current images are `ubuntu-24.04-minimal-cloudimg-{arm64,amd64}-docker`
  ([`embedded/images/images.txt`](https://github.com/abiosoft/colima/blob/main/embedded/images/images.txt)),
  built from Canonical's noble minimal cloud image
  ([colima-core `scripts/cloud-image.sh`](https://github.com/abiosoft/colima-core/blob/main/scripts/cloud-image.sh)).
  User reports show the running kernel is `6.8.0-*-generic`, for example
  `6.8.0-117-generic` in Nov 2026
  ([colima#1664](https://github.com/abiosoft/colima/issues/1664),
  [#1355](https://github.com/abiosoft/colima/issues/1355)).
- **Kernel config (confirmed).** Extracted from Ubuntu's
  `linux-modules-6.8.0-149-generic` packages for arm64
  ([ports.ubuntu.com](http://ports.ubuntu.com/ubuntu-ports/pool/main/l/linux/))
  and amd64
  ([archive.ubuntu.com](http://archive.ubuntu.com/ubuntu/pool/main/l/linux/)).
  Both are identical for these options:
  ```
  CONFIG_DEBUG_INFO_BTF=y
  CONFIG_DEBUG_INFO_BTF_MODULES=y
  CONFIG_BPF_KPROBE_OVERRIDE=y
  CONFIG_FUNCTION_ERROR_INJECTION=y
  CONFIG_DYNAMIC_FTRACE_WITH_DIRECT_CALLS=y
  CONFIG_BPF_EVENTS=y
  CONFIG_FTRACE_SYSCALLS=y
  CONFIG_SECURITY=y
  CONFIG_AUDIT=y
  CONFIG_CGROUP_BPF=y
  CONFIG_BPF_LSM=y
  CONFIG_LSM="landlock,lockdown,yama,integrity,apparmor"   # no "bpf"
  ```
  This means BTF, kprobes, tracepoints, `Sigkill` and `Override` on
  syscalls are all available. `Override` on `security_*` should also work
  through fmod_ret on 6.8. **`lsmhooks` will not load by default**,
  because `bpf` is not an active LSM. Adding `lsm=…,bpf` to the VM's
  kernel command line should fix that, but it is untested on Colima.
- **The `/procHost` fix should work (unverified).** With Colima's docker
  runtime, `dockerd` runs inside the Lima VM, so a bind-mount source such
  as `/proc` resolves to the VM's `/proc`. This is inference from the
  architecture and has not been tried. Confirm by checking that Tetragon's
  log has **no** `inode mismatch` warning.
- **Caveat: the kernel is pinned to the image.** Colima pins the image
  version per release, so the exact kernel varies with the Colima release
  and with in-VM apt upgrades. Run `tetra probe` once to confirm.

## Related: CI (GitHub-hosted Ubuntu runners)

Not part of this ticket, but useful for the CI ticket. Ubuntu's noble
`linux-azure` kernels (6.11, 6.14 and 6.17 HWE) have `DEBUG_INFO_BTF=y`,
`BPF_KPROBE_OVERRIDE=y` and `BPF_LSM=y`. They do **not** list `bpf` in
`CONFIG_LSM`
([archive.ubuntu.com linux-azure-6.17](http://archive.ubuntu.com/ubuntu/pool/main/l/linux-azure-6.17/)).
The runner's actual kernel is unverified, so check `uname -r` in a job.
The expected capability set is therefore the same as Colima: observe,
`Sigkill` and `Override` work, `lsmhooks` do not. Using the same setup
locally and in CI is a point in Colima's favour.

## Implications for Guardrails

- **Design Guardrails around kprobe/tracepoint plus `Sigkill`, and
  syscall `Override`.** That is the capability set that works on both
  Colima and CI. Prefer `Override` (optionally with `Sigkill`) for
  "must not happen" Guardrails such as exfiltration writes, because
  `Sigkill` alone can let the triggering `write()` complete.
- **Avoid `lsmhooks` Guardrails** unless we accept a non-default kernel
  boot argument in both Colima and CI. Use `security_*` kprobes with
  `Override` (fmod_ret) instead. That gives the same LSM-level
  interception without needing BPF LSM to be active.
- **Every local setup must check pod attribution.** Pod-scoped
  `TracingPolicyNamespaced` and `podSelector` Guardrails fail **silently**
  if procfs is not the host's (#4883). The smoke test should assert that a
  rogue Scenario's `process_kprobe` event carries `pod.name`, not just
  that some event arrived.

## Verification checklist (run once on a Mac)

```shell
colima start --runtime docker --cpu 4 --memory 8   # vmType vz or qemu
colima ssh -- uname -r                              # expect 6.8.0-*-generic
colima ssh -- sh -c 'zgrep -E "BPF_KPROBE_OVERRIDE|DEBUG_INFO_BTF=" /boot/config-$(uname -r) || grep -E "BPF_KPROBE_OVERRIDE|DEBUG_INFO_BTF=" /boot/config-$(uname -r)'
colima ssh -- cat /sys/kernel/security/lsm          # "bpf" expected absent

# kind with host /proc, per Tetragon's kind instructions
kind create cluster --config kind-config.yaml       # extraMounts /proc -> /procHost
helm install tetragon cilium/tetragon -n kube-system --set tetragon.hostProcPath=/procHost
kubectl -n kube-system logs ds/tetragon -c tetragon | grep -E 'inode mismatch|Read ProcFS|BPF detected features'
#   want: no "inode mismatch"; "appended N/N"; override_return: true, signal: true, fmodret: true

kubectl run bpf-probe --image=quay.io/cilium/tetragon-ci:latest \
  --privileged --restart=Never -it --rm --command -- tetra probe
```

Then apply one `Sigkill` policy and one syscall `Override` policy, and
check that a pod-attributed event plus the enforced effect are observed.
Running the same checklist on Docker Desktop or OrbStack would resolve
their "unknown" cells.

## Open questions

- Does Docker Desktop's current kernel set `CONFIG_BPF_KPROBE_OVERRIDE`?
  Does `hostPath: /proc` in kind reach the VM's procfs on DD?
- Same questions for OrbStack's current kernel.
- Does adding `lsm=…,bpf` to the Colima VM's kernel command line survive
  restarts and work with both `vz` and `qemu`?
