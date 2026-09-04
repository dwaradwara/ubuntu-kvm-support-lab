# INC004 — KVM Storage Snapshot and Recovery Validation

## Summary

A secondary qcow2 storage volume was created and attached to the KVM virtual machine `ubuntu-guest-01`.

The new disk was formatted with ext4, mounted inside the guest, configured for persistent mounting using `/etc/fstab`, and validated across a reboot.

A multi-disk internal snapshot named `day3-baseline` was then created while the VM was powered off.

Changes were deliberately introduced on both the primary system disk and secondary data disk after the snapshot.

The VM was subsequently reverted to the snapshot to validate recovery.

The rollback successfully removed all post-snapshot changes from both disks while preserving data that existed before the snapshot.

---

## Environment

### Hypervisor

- QEMU/KVM
- libvirt
- Ubuntu host running under WSL
- Virtual Machine Manager

### Virtual Machine

VM:

`ubuntu-guest-01`

Guest hostname:

`lab-guest-01`

Guest OS:

Ubuntu Server 24.04.4 LTS

Primary disk:

`vda`

Secondary test disk:

`vdb`

---

## Storage Pool

The existing libvirt storage pool was inspected:

```bash
virsh -c qemu:///system pool-list --all
```

Available pools:

- `default`
- `lab-pool`

The VM storage was confirmed to reside inside:

```text
/var/lib/libvirt/images/lab-pool/
```

Pool information was inspected using:

```bash
virsh -c qemu:///system pool-info lab-pool
```

Observed capacity was approximately:

```text
Capacity:   1006.85 GiB
Allocation: 9.87 GiB
Available:  996.98 GiB
```

---

## Existing VM Disk Investigation

The VM block devices were inspected using:

```bash
virsh -c qemu:///system domblklist ubuntu-guest-01 --details
```

Primary VM disk:

```text
/var/lib/libvirt/images/lab-pool/ubuntu-guest-01.qcow2
```

The qcow2 metadata was inspected while the VM was running using:

```bash
sudo qemu-img info --force-share \
/var/lib/libvirt/images/lab-pool/ubuntu-guest-01.qcow2
```

Observed:

```text
file format: qcow2
virtual size: 20 GiB
disk size: approximately 4.11 GiB
corrupt: false
```

This demonstrated qcow2 thin provisioning because the guest-visible virtual capacity was substantially larger than the physical host allocation.

---

## Secondary Disk Creation

A new 5 GiB qcow2 volume was created:

```bash
virsh -c qemu:///system vol-create-as \
lab-pool \
day3-test-disk.qcow2 \
5G \
--format qcow2
```

The volume was verified using:

```bash
virsh -c qemu:///system vol-list lab-pool
```

New volume:

```text
/var/lib/libvirt/images/lab-pool/day3-test-disk.qcow2
```

Metadata inspection:

```bash
sudo qemu-img info \
/var/lib/libvirt/images/lab-pool/day3-test-disk.qcow2
```

Observed:

```text
file format: qcow2
virtual size: 5 GiB
disk size: approximately 196 KiB
corrupt: false
```

This again demonstrated thin provisioning.

---

## Disk Attachment

The new volume was attached to the running VM as a virtio disk:

```bash
virsh -c qemu:///system attach-disk ubuntu-guest-01 \
/var/lib/libvirt/images/lab-pool/day3-test-disk.qcow2 \
vdb \
--targetbus virtio \
--subdriver qcow2 \
--persistent
```

Result:

```text
Disk attached successfully
```

Host-side verification:

```bash
virsh -c qemu:///system domblklist ubuntu-guest-01 --details
```

Observed:

```text
vda -> ubuntu-guest-01.qcow2
vdb -> day3-test-disk.qcow2
```---

## Guest Disk Detection

Inside the Ubuntu guest:

```bash
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINTS
```

Observed:

```text
vda   20G  disk
vdb    5G  disk
```

The new `vdb` device had no filesystem or mount point, confirming it was a blank disk.

---

## Filesystem Creation

An ext4 filesystem was created:

```bash
sudo mkfs.ext4 /dev/vdb
```

Filesystem creation completed successfully.

The filesystem UUID was:

```text
6b4f2fee-71d6-4f44-ab09-9363b63fe8d4
```

---

## Mount Configuration

A mount point was created:

```bash
sudo mkdir -p /mnt/day3-test
```

The disk was mounted:

```bash
sudo mount /dev/vdb /mnt/day3-test
```

Verification:

```bash
df -hT /mnt/day3-test
```

Observed approximately:

```text
/dev/vdb  ext4  4.9G  /mnt/day3-test
```

---

## Write Validation

A validation file was written:

```bash
echo "Day 3 storage validation" | \
sudo tee /mnt/day3-test/validation.txt
```

Verification:

```bash
cat /mnt/day3-test/validation.txt
```

Result:

```text
Day 3 storage validation
```

This confirmed successful read/write access to the secondary disk.---

## Persistent Mount Configuration

The filesystem UUID was verified:

```bash
sudo blkid /dev/vdb
```

The existing `/etc/fstab` was backed up:

```bash
sudo cp /etc/fstab /etc/fstab.backup-day3
```

The following entry was added:

```text
UUID=6b4f2fee-71d6-4f44-ab09-9363b63fe8d4 /mnt/day3-test ext4 defaults,nofail 0 2
```

The configuration was validated using:

```bash
sudo findmnt --verify --verbose
```

Result:

```text
0 parse errors
0 errors
```

Systemd configuration was reloaded:

```bash
sudo systemctl daemon-reload
```

The filesystem was unmounted:

```bash
sudo umount /mnt/day3-test
```

All `/etc/fstab` entries were then mounted:

```bash
sudo mount -a
```

Verification:

```bash
findmnt /mnt/day3-test
```

The secondary disk successfully remounted.

---

## Reboot Persistence Validation

The guest was rebooted.

After reboot:

```bash
findmnt /mnt/day3-test
```

Observed:

```text
TARGET          SOURCE    FSTYPE
/mnt/day3-test  /dev/vdb  ext4
```

The original validation file remained available:

```bash
cat /mnt/day3-test/validation.txt
```

Result:

```text
Day 3 storage validation
```

This confirmed the persistent `/etc/fstab` configuration was functioning correctly.

---

# Snapshot Recovery Test

## Snapshot Preparation

Existing snapshots were checked:

```bash
virsh -c qemu:///system snapshot-list ubuntu-guest-01
```

No previous snapshots existed.

The VM was shut down before creating the snapshot:

```bash
virsh -c qemu:///system shutdown ubuntu-guest-01
```

VM state was verified:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```

Result:

```text
shut off
```---

## Baseline Snapshot

A snapshot named `day3-baseline` was created:

```bash
virsh -c qemu:///system snapshot-create-as \
ubuntu-guest-01 \
day3-baseline \
--description "Day 3 baseline before snapshot recovery test" \
--atomic
```

Result:

```text
Domain snapshot day3-baseline created
```

Snapshot verification:

```bash
virsh -c qemu:///system snapshot-list ubuntu-guest-01
```

Observed:

```text
day3-baseline
```

---

## Multi-Disk Snapshot Verification

The snapshot XML was inspected:

```bash
virsh -c qemu:///system snapshot-dumpxml \
ubuntu-guest-01 \
day3-baseline
```

The disk configuration showed:

```xml
<disk name='vda' snapshot='internal'/>
<disk name='vdb' snapshot='internal'/>
<disk name='sda' snapshot='no'/>
```

This confirmed both writable VM disks were protected by the snapshot.

The CD-ROM device `sda` was correctly excluded.

---

## Post-Snapshot Changes

The VM was started again.

Two files were deliberately created after the baseline snapshot.

### System disk test

```bash
echo "Created AFTER day3-baseline snapshot - system disk" | \
sudo tee /root/after-snapshot-vda.txt
```

### Secondary disk test

```bash
echo "Created AFTER day3-baseline snapshot - data disk" | \
sudo tee /mnt/day3-test/after-snapshot-vdb.txt
```

Both files were verified successfully.

These represented state changes that should disappear following snapshot recovery.---

## Snapshot Revert

The VM was shut down cleanly:

```bash
sudo shutdown -h now
```

Host verification:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```

Result:

```text
shut off
```

The VM was reverted:

```bash
virsh -c qemu:///system snapshot-revert \
ubuntu-guest-01 \
day3-baseline
```

Result:

```text
Domain snapshot day3-baseline reverted
```

The VM remained powered off because the snapshot was captured in the shut-off state.

---

## Recovery Validation

The VM was started and the guest was accessed again.

### System disk validation

```bash
sudo ls -l /root/after-snapshot-vda.txt
```

Result:

```text
No such file or directory
```

The post-snapshot system disk change had been removed.

### Secondary disk validation

```bash
ls -l /mnt/day3-test/after-snapshot-vdb.txt
```

Result:

```text
No such file or directory
```

The post-snapshot secondary disk change had also been removed.

### Pre-snapshot data validation

```bash
cat /mnt/day3-test/validation.txt
```

Result:

```text
Day 3 storage validation
```

The original pre-snapshot data remained intact.

---

## Result

Recovery was successful.

The snapshot restored both writable VM disks to the baseline state:

```text
vda -> restored
vdb -> restored
```

Post-snapshot changes disappeared from both disks.

Pre-snapshot data remained available.

---

## Technical Findings

1. A qcow2 disk can expose significantly more virtual capacity than the physical storage initially allocated.
2. A newly attached virtual disk is not usable by applications until the guest operating system creates a filesystem and mounts it.
3. Persistent disk mounts should use filesystem UUIDs instead of relying only on device names such as `/dev/vdb`.
4. `/etc/fstab` changes should be validated before rebooting.
5. `mount -a` provides a safe way to test mount configuration before performing a restart.
6. A snapshot should be inspected to verify which VM disks are actually protected.
7. Multi-disk recovery testing is stronger than assuming snapshot creation alone guarantees recoverability.
8. A successful recovery test requires validating both removal of post-snapshot changes and preservation of pre-snapshot data.

---

## Support Troubleshooting Method

The workflow used throughout the exercise was:

```text
Inspect
→ Establish baseline
→ Make controlled change
→ Validate
→ Introduce failure/change
→ Recover
→ Validate recovery
→ Document evidence
```

This prevents assuming that a storage or recovery operation succeeded based only on command exit status.

---

## Final Status

```text
Secondary qcow2 creation        PASS
Virtio disk attachment          PASS
Guest device detection          PASS
ext4 filesystem creation        PASS
Read/write validation           PASS
Persistent UUID mount           PASS
Reboot persistence              PASS
Multi-disk snapshot             PASS
Snapshot revert                 PASS
System disk recovery            PASS
Secondary disk recovery         PASS
Pre-snapshot data preservation  PASS
```

**INC004 status: RESOLVED / VALIDATED**
