# INC015 — Controlled Memory Cgroup OOM Kill and Service Isolation

## Summary

A controlled out-of-memory incident was reproduced and validated on the Ubuntu KVM guest without exhausting the entire virtual machine.

Instead of consuming all host memory, the test process was placed inside a dedicated systemd transient service with a strict cgroup memory limit.

The test environment used:

```text
MemoryMax      → 64 MiB
MemorySwapMax  → 0
Test workload  → Python allocation of ~256 MiB
```

The Python process attempted to allocate substantially more memory than its cgroup was permitted to use.

The Linux kernel terminated only the constrained test process.

Systemd recorded:

```text
Result=oom-kill
ExecMainStatus=9
```

Service logs confirmed:

```text
A process of this unit has been killed by the OOM killer.
Main process exited, code=killed, status=9/KILL
Failed with result 'oom-kill'.
```

Kernel logs provided direct memory-cgroup evidence:

```text
constraint=CONSTRAINT_MEMCG
Memory cgroup out of memory
Killed process ... (python3)
```

The core VM services remained healthy throughout:

```text
nginx                    → active
postgresql               → active
prometheus               → active
prometheus-node-exporter → active
```

Host memory remained healthy after the incident, with approximately:

```text
Available RAM → 1.5 GiB
Host swap     → 1.8 GiB enabled
Swap used     → 0 B
```

The temporary systemd unit was then cleared.

Final validation showed:

```text
INC015 transient unit     → removed
Core services             → active
Host memory               → healthy
Host swap                 → unchanged
```

This demonstrated a controlled cgroup-level OOM event rather than an uncontrolled host-wide memory exhaustion event.

---

## Environment

### Virtual Machine

VM:

```text
ubuntu-guest-01
```

Guest hostname:

```text
lab-guest-01
```

Guest OS:

```text
Ubuntu Server 24.04.4 LTS
```

Primary IP:

```text
192.168.122.170
```

---

## Initial Memory Baseline

Host memory was checked:

```bash
free -h
```

Observed approximately:

```text
               total    used    free    shared   buff/cache   available
Mem:           1.9Gi    466Mi   285Mi   33Mi     1.4Gi        1.5Gi
Swap:          1.8Gi      0B    1.8Gi
```

This showed that the VM had sufficient free memory and was not already under host-wide memory pressure.

---

## Host Swap Baseline

Swap configuration was checked:

```bash
swapon --show
```

Observed:

```text
NAME      TYPE  SIZE  USED  PRIO
/swap.img file  1.8G  0B   -2
```

Host-level swap was therefore enabled and unused.

This was important because the INC015 test needed to avoid modifying global swap configuration.

---

## Cgroup Version Validation

The cgroup filesystem type was checked:

```bash
stat -fc %T /sys/fs/cgroup
```

Observed:

```text
cgroup2fs
```

This confirmed that the guest was using cgroup v2.

---

## Memory Controller Validation

Available cgroup controllers were checked:

```bash
cat /sys/fs/cgroup/cgroup.controllers
```

Observed controllers included:

```text
cpuset
cpu
io
memory
hugetlb
pids
rdma
misc
```

The presence of:

```text
memory
```

confirmed that memory limits could be applied to a dedicated cgroup.

---

## systemd-run Availability

The transient-unit tool was checked:

```bash
command -v systemd-run || \
echo "systemd-run not available"
```

Observed:

```text
/usr/bin/systemd-run
```

This allowed the OOM test to be isolated inside a dedicated systemd-managed cgroup.

---

## Core Service Baseline

Important persistent services were checked before the test:

```bash
systemctl is-active \
nginx \
postgresql \
prometheus \
prometheus-node-exporter
```

Observed:

```text
active
active
active
active
```

This established a baseline that could later be compared against the post-OOM state.

---

## Safety Design

A host-wide OOM test was deliberately avoided.

Exhausting the VM's full memory could have killed unrelated processes such as:

```text
sshd
PostgreSQL
Prometheus
Nginx
system services
```

and could have disrupted the entire lab.

Instead, a dedicated transient unit was created with:

```text
MemoryMax=64M
MemorySwapMax=0
```

This meant the test process could use only approximately 64 MiB of memory and could not fall back to swap within its own cgroup.

Host swap remained enabled normally for the rest of the operating system.

---

## Controlled OOM Workload

The controlled workload was started with:

```bash
sudo systemd-run \
  --unit=inc015-oom \
  --property=MemoryMax=64M \
  --property=MemorySwapMax=0 \
  /usr/bin/python3 -c \
  'import time; x=bytearray(256*1024*1024); time.sleep(60)'
```

The test attempted to allocate approximately:

```text
256 MiB
```

while the cgroup allowed only:

```text
64 MiB
```

The allocation was therefore intentionally larger than the permitted memory ceiling.

---

## OOM Failure Result

The transient service failed as expected.

Systemd reported:

```text
inc015-oom.service: Failed with result 'oom-kill'.
```

The service properties were inspected:

```bash
systemctl show inc015-oom.service \
-p Result \
-p ExecMainCode \
-p ExecMainStatus \
-p MemoryCurrent \
-p MemoryPeak
```

Observed:

```text
Result=oom-kill
ExecMainCode=2
ExecMainStatus=9
MemoryCurrent=[not set]
MemoryPeak=[not set]
```

The critical evidence was:

```text
Result=oom-kill
ExecMainStatus=9
```

Status `9` corresponds to termination by `SIGKILL`.

---

## systemd OOM Evidence

The transient service journal was inspected:

```bash
journalctl \
-u inc015-oom.service \
-n 30 \
--no-pager
```

Observed messages included:

```text
Started inc015-oom.service
A process of this unit has been killed by the OOM killer.
Main process exited, code=killed, status=9/KILL
Failed with result 'oom-kill'.
```

This proved that systemd recognized the service failure specifically as an OOM event.

---

## Kernel OOM Evidence

Kernel logs were inspected:

```bash
sudo journalctl -k \
--since "2 minutes ago" \
--no-pager | \
grep -Ei \
'oom|out of memory|killed process|memory cgroup' | \
tail -n 30
```

Observed evidence included:

```text
python3 invoked oom-killer
```

and:

```text
Memory cgroup stats for /system.slice/inc015-oom.service
```

The kernel also reported:

```text
oom-kill:constraint=CONSTRAINT_MEMCG
```

followed by:

```text
Memory cgroup out of memory:
Killed process ... (python3)
```

This was direct proof that the failure occurred because of a memory-cgroup constraint.

---

## Cgroup Isolation Evidence

The kernel identified the affected memory cgroup as:

```text
/system.slice/inc015-oom.service
```

The constraint type was:

```text
CONSTRAINT_MEMCG
```

This distinguished the incident from a global host OOM.

The kernel selected the Python workload belonging to the test unit rather than an unrelated system process.

---

## Test Memory Limit Validation

The configured service properties were inspected:

```bash
systemctl show inc015-oom.service \
-p MemoryMax \
-p MemorySwapMax \
-p Result \
-p ExecMainStatus
```

Observed:

```text
Result=oom-kill
ExecMainStatus=9
MemoryMax=67108864
MemorySwapMax=0
```

The value:

```text
67108864 bytes
```

equals:

```text
64 MiB
```

This confirmed the exact memory ceiling used during the incident.

---

## Failure Chain

The controlled failure occurred as follows:

```text
Transient systemd unit starts
→ systemd creates dedicated cgroup
→ MemoryMax limits cgroup to 64 MiB
→ MemorySwapMax prevents cgroup swap usage
→ Python requests ~256 MiB
→ cgroup reaches memory ceiling
→ kernel invokes memcg OOM handling
→ Python process selected for termination
→ process receives SIGKILL
→ systemd records Result=oom-kill
```

The incident therefore behaved exactly as designed.---

## Host Isolation Validation

After the OOM kill, the persistent services were checked again:

```bash
systemctl is-active \
nginx \
postgresql \
prometheus \
prometheus-node-exporter
```

Observed:

```text
active
active
active
active
```

This confirmed that the OOM event remained isolated to the INC015 transient cgroup.

No unrelated production-style service was terminated.

---

## Host Memory After Incident

Host memory was checked again:

```bash
free -h
```

Observed approximately:

```text
               total    used    free    shared   buff/cache   available
Mem:           1.9Gi    471Mi   272Mi   33Mi     1.4Gi        1.5Gi
Swap:          1.8Gi      0B    1.8Gi
```

The VM retained approximately:

```text
1.5 GiB available RAM
```

after the event.

This showed that the host itself was not experiencing global memory exhaustion.

---

## Host Swap After Incident

Swap state was checked again:

```bash
swapon --show
```

Observed:

```text
NAME      TYPE  SIZE  USED  PRIO
/swap.img file  1.8G  0B   -2
```

This confirmed that:

```text
Host swap remained enabled
Host swap remained unused
```

The `MemorySwapMax=0` setting affected only the test cgroup.

---

## Root Cause

The root cause was an intentional memory-cgroup limit violation.

The test workload requested:

```text
~256 MiB
```

while the cgroup allowed:

```text
64 MiB
```

and:

```text
MemorySwapMax=0
```

prevented the test process from using swap.

The kernel therefore had no reclaim path inside the constrained cgroup and invoked the cgroup OOM killer.

Root cause:

```text
Application memory demand exceeded cgroup MemoryMax
```

The event was not caused by:

```text
Host RAM exhaustion
Host swap exhaustion
PostgreSQL memory growth
Prometheus memory growth
Nginx memory growth
Kernel instability
```

---

## Why This Was Not a Host-Wide OOM

A host-wide OOM would typically involve global memory exhaustion and could terminate unrelated processes.

That did not occur.

Evidence:

```text
CONSTRAINT_MEMCG
```

identified the OOM scope as the memory cgroup.

The kernel log referenced:

```text
/system.slice/inc015-oom.service
```

and killed:

```text
python3
```

inside that cgroup.

At the same time:

```text
nginx                    → active
postgresql               → active
prometheus               → active
prometheus-node-exporter → active
```

and the host still had substantial available memory.

This directly distinguishes:

```text
cgroup-scoped OOM
```

from:

```text
global system OOM
```

---

## OOM Signal Interpretation

Systemd reported:

```text
ExecMainStatus=9
```

The process therefore terminated because of:

```text
SIGKILL
```

This is consistent with Linux OOM-killer behavior.

The process did not exit gracefully and did not handle the failure itself.

---

## Operational Impact

The incident affected only:

```text
inc015-oom.service
```

Impact:

```text
Test process terminated
Transient unit failed
No persistent service outage
No host reboot
No SSH loss
No database outage
No monitoring outage
```

This was the intended safety boundary for the experiment.

---

## Recovery

No service restart or host recovery action was required.

The operating system automatically reclaimed the memory associated with the killed process.

The persistent services remained healthy throughout.

The only remaining cleanup task was to remove the failed transient systemd unit state.

---

## Transient Unit Cleanup

The failed state was reset:

```bash
sudo systemctl reset-failed \
inc015-oom.service
```

The unit was then checked:

```bash
systemctl status \
inc015-oom.service \
--no-pager -l
```

Observed:

```text
Unit inc015-oom.service could not be found.
```

This confirmed that the transient unit no longer existed after the failed-state reset.

---

## Unit Removal Validation

The systemd unit list was checked:

```bash
systemctl list-units --all | \
grep inc015-oom || \
echo "INC015 transient unit removed"
```

Observed:

```text
INC015 transient unit removed
```

This confirmed complete cleanup of the temporary OOM test service.

---

## Final Core Service Validation

The persistent services were checked one final time:

```bash
systemctl is-active \
nginx \
postgresql \
prometheus \
prometheus-node-exporter
```

Observed:

```text
active
active
active
active
```

This confirmed that cleanup had no negative effect on the base lab environment.

---

## Before / During / After Comparison

### Before OOM

```text
Host memory          → healthy
Host swap            → enabled
Core services        → active
INC015 unit          → absent
```

### During OOM

```text
INC015 MemoryMax     → 64 MiB
INC015 MemorySwapMax → 0
Python allocation    → ~256 MiB
Kernel constraint    → CONSTRAINT_MEMCG
Python process       → killed
systemd Result       → oom-kill
Core services        → unaffected
```

### After Cleanup

```text
INC015 unit          → removed
Host memory          → healthy
Host swap            → unchanged
Core services        → active
```

This established a complete:

```text
healthy baseline
→ controlled cgroup OOM
→ automatic memory recovery
→ cleanup
```

lifecycle.

---

## Technical Findings

1. A cgroup OOM can occur even when the host has substantial free memory.
2. `CONSTRAINT_MEMCG` is strong evidence that the OOM was scoped to a memory cgroup.
3. `MemoryMax` can be used to reproduce memory-pressure failures safely.
4. `MemorySwapMax=0` prevents a constrained unit from escaping the memory limit through swap.
5. Host swap configuration does not need to be changed to test cgroup OOM behavior.
6. `Result=oom-kill` in systemd is direct evidence of an OOM-related unit failure.
7. `ExecMainStatus=9` indicates termination by `SIGKILL`.
8. Kernel OOM logs should be checked alongside systemd logs.
9. The cgroup path in the kernel log helps identify the affected service boundary.
10. A host-wide memory stress test is unnecessarily risky for a shared support lab.
11. Controlled resource limits provide cleaner and safer incident reproduction.
12. Core service health should be checked after any resource-exhaustion test.
13. Host memory and swap should be validated after the event.
14. OOM recovery may require no application fix if the failure was intentionally induced.
15. Transient units should be removed after controlled testing.

---

## Support Troubleshooting Method

The workflow used was:

```text
Check host memory
→ inspect host swap
→ confirm cgroup v2
→ confirm memory controller
→ confirm systemd-run availability
→ establish core-service baseline
→ choose safe cgroup-scoped test
→ configure MemoryMax
→ configure MemorySwapMax
→ start controlled memory allocation
→ observe unit failure
→ inspect systemd result
→ inspect service journal
→ inspect kernel OOM logs
→ identify CONSTRAINT_MEMCG
→ identify killed Python process
→ confirm configured memory limits
→ verify core services remain active
→ verify host memory remains healthy
→ verify host swap remains enabled
→ identify cgroup limit as root cause
→ reset failed transient unit
→ verify unit removal
→ perform final core-service validation
```

---

## Final Status

```text
Host memory baseline                 PASS
Host swap baseline                   PASS
cgroup v2 validation                 PASS
Memory controller validation         PASS
systemd-run availability             PASS
Core-service baseline                PASS
Safe isolation design                PASS
Transient cgroup creation            PASS
MemoryMax enforcement                PASS
MemorySwapMax enforcement            PASS
Controlled allocation                PASS
OOM reproduction                     PASS
systemd oom-kill result               PASS
SIGKILL validation                   PASS
Service journal evidence             PASS
Kernel OOM evidence                  PASS
CONSTRAINT_MEMCG validation          PASS
Killed-process identification        PASS
Memory-limit validation              PASS
Core-service isolation validation    PASS
Host-memory post-check               PASS
Host-swap post-check                 PASS
Root-cause identification            PASS
Transient-unit cleanup               PASS
Unit-removal validation              PASS
Final core-service validation        PASS
```

**INC015 status: RESOLVED / VALIDATED**
