# INC005 — Disk Full Recovery

## Summary

A controlled disk-full condition was created on the secondary KVM data volume mounted at `/mnt/day3-test`.

The filesystem reached 100% utilization, causing an application-style write operation to fail with:

```text
No space left on device
```

The incident was investigated using filesystem capacity checks, inode checks, and directory-level disk usage analysis.

The investigation confirmed that the failure was caused by block-space exhaustion rather than inode exhaustion.

A single large test file consuming approximately 4.4 GiB was identified as the primary space consumer.

The offending file was removed, filesystem capacity recovered, and the failed write operation was retried successfully.

---

## Environment

### Virtual Machine

VM:

`ubuntu-guest-01`

Guest hostname:

`lab-guest-01`

Guest OS:

Ubuntu Server 24.04.4 LTS

### Filesystems

Root filesystem:

```text
/dev/mapper/ubuntu--vg-ubuntu--lv
```

Secondary test filesystem:

```text
/dev/vdb
```

Mount point:

```text
/mnt/day3-test
```

---

## Baseline Validation

The root filesystem was checked first:

```bash
df -hT /
```

Observed:

```text
Size:      9.8G
Used:      4.6G
Available: 4.8G
Usage:     49%
```

The root filesystem was healthy and was intentionally left untouched.

The dedicated secondary test filesystem was then checked:

```bash
df -hT /mnt/day3-test
```

Observed:

```text
/dev/vdb  ext4  4.9G  28K  4.6G  1%  /mnt/day3-test
```

Directory usage was also checked:

```bash
sudo du -sh /mnt/day3-test
```

Observed:

```text
24K  /mnt/day3-test
```

This established the baseline before introducing disk pressure.---

## Controlled Disk Pressure

A dedicated incident directory was created:

```bash
sudo mkdir -p /mnt/day3-test/inc005
```

Ownership was assigned to the guest user:

```bash
sudo chown ubuntu:ubuntu /mnt/day3-test/inc005
```

A large test file was created to consume most of the available space:

```bash
fallocate -l 4.3G /mnt/day3-test/inc005/large-test-file.bin
```

Filesystem usage was checked again:

```bash
df -hT /mnt/day3-test
```

Observed:

```text
/dev/vdb  ext4  4.9G  4.4G  247M  95%  /mnt/day3-test
```

The volume had entered a high disk-usage condition.

---

## Failure Reproduction

An application-style write test attempted to write an additional 300 MiB:

```bash
dd if=/dev/zero \
of=/mnt/day3-test/inc005/app-write.bin \
bs=1M \
count=300 \
status=progress
```

The write failed with:

```text
dd: error writing '/mnt/day3-test/inc005/app-write.bin': No space left on device
```

The partial write reached approximately:

```text
247 MiB
```

before the filesystem became completely full.

---

## Initial Investigation

Filesystem capacity was checked:

```bash
df -hT /mnt/day3-test
```

Observed:

```text
/dev/vdb  ext4  4.9G  4.6G  0  100%  /mnt/day3-test
```

This confirmed that the filesystem had no available block space.

Inode usage was then checked:

```bash
df -i /mnt/day3-test
```

Observed:

```text
Inodes: 327680
IUsed:  15
IFree:  327665
IUse%:  1%
```

This ruled out inode exhaustion.

The failure was therefore caused by block-space exhaustion rather than inode exhaustion.---

## Root Cause Isolation

Directory-level usage was inspected:

```bash
sudo du -xh --max-depth=2 /mnt/day3-test | sort -h
```

Observed:

```text
16K   /mnt/day3-test/lost+found
4.6G  /mnt/day3-test
4.6G  /mnt/day3-test/inc005
```

The files inside the incident directory were then inspected:

```bash
ls -lh /mnt/day3-test/inc005
```

Observed:

```text
247M  app-write.bin
4.4G  large-test-file.bin
```

A second usage check confirmed the same:

```bash
sudo du -ah /mnt/day3-test/inc005 | sort -h | tail -n 10
```

Observed:

```text
247M  /mnt/day3-test/inc005/app-write.bin
4.4G  /mnt/day3-test/inc005/large-test-file.bin
4.6G  /mnt/day3-test/inc005
```

The primary space consumer was therefore:

```text
large-test-file.bin
```

with approximately 4.4 GiB of usage.

---

## Recovery

The confirmed offending file was removed:

```bash
rm /mnt/day3-test/inc005/large-test-file.bin
```

Filesystem capacity was immediately checked again:

```bash
df -hT /mnt/day3-test
```

Observed:

```text
/dev/vdb  ext4  4.9G  247M  4.4G  6%  /mnt/day3-test
```

Available capacity was successfully restored.

---

## Write Retry

The same 300 MiB write operation was retried:

```bash
dd if=/dev/zero \
of=/mnt/day3-test/inc005/app-write.bin \
bs=1M \
count=300 \
status=progress
```

Result:

```text
300+0 records in
300+0 records out
314572800 bytes copied
```

The write completed successfully with no `No space left on device` error.

The resulting file was verified:

```bash
ls -lh /mnt/day3-test/inc005/app-write.bin
```

Observed:

```text
300M  /mnt/day3-test/inc005/app-write.bin
```

Filesystem usage after recovery and validation:

```bash
df -hT /mnt/day3-test
```

Observed:

```text
/dev/vdb  ext4  4.9G  301M  4.3G  7%  /mnt/day3-test
```

---

## Result

The incident was successfully resolved.

The failure mechanism was:

```text
Large file growth
→ filesystem block space exhausted
→ application write failed
→ "No space left on device"
```

Recovery was:

```text
Identify largest consumer
→ remove confirmed offending file
→ restore free capacity
→ retry failed write
→ validate success
```

---

## Technical Findings

1. `No space left on device` can be caused by block exhaustion or inode exhaustion, so both must be checked.
2. `df -hT` confirms filesystem capacity and utilization.
3. `df -i` distinguishes inode exhaustion from block-space exhaustion.
4. `du` helps identify which directories are consuming the filesystem.
5. Large files should be identified before deletion rather than removing data blindly.
6. Recovery should be validated by retrying the same failed operation.
7. A system should not be declared recovered only because free space increased.
8. Using a dedicated test volume allowed the incident to be reproduced without risking the root filesystem.

---

## Support Troubleshooting Method

The workflow used was:

```text
Symptom
→ Capacity check
→ Inode check
→ Directory usage analysis
→ File-level isolation
→ Root cause
→ Controlled cleanup
→ Retry
→ Validation
```

This approach avoids guessing and confirms the exact failure mode before remediation.

---

## Final Status

```text
Baseline capacity check       PASS
Controlled disk pressure      PASS
Write failure reproduction    PASS
Filesystem full detection     PASS
Inode exhaustion ruled out    PASS
Largest consumer identified   PASS
Disk cleanup                  PASS
Capacity recovery             PASS
Write retry                   PASS
Post-recovery validation      PASS
```

**INC005 status: RESOLVED / VALIDATED**
