# INC009 — Cloud-init Datasource Detection and Recovery

## Summary

A cloud-init initialization issue was investigated on the Ubuntu KVM guest.

The guest initially reported:

```text
status: disabled
extended_status: disabled
boot_status_code: disabled-by-marker-file
detail: Cloud-init disabled by /etc/cloud/cloud-init.disabled
```

The marker file was confirmed at:

```text
/etc/cloud/cloud-init.disabled
```

Inspection showed that it had been created intentionally by the Ubuntu live installer after the first boot.

The marker contained instructions indicating that cloud-init could be re-enabled using:

```bash
sudo cloud-init clean --machine-id
```

After running the supported clean operation and rebooting, cloud-init still did not start.

The new status was:

```text
status: disabled
boot_status_code: disabled-by-generator
detail: Cloud-init disabled by cloud-init-generator
```

Further investigation of datasource detection showed:

```text
MODE=search
ON_NOTFOUND=disabled
No ds found [mode=search, notfound=disabled].
Disabled cloud-init
```

The VM was a local KVM guest without an external cloud metadata service, so no datasource could be discovered automatically.

A local NoCloud datasource was therefore created under:

```text
/var/lib/cloud/seed/nocloud
```

with:

```text
meta-data
user-data
network-config
```

Cloud-init was cleaned and the VM was restarted.

During the fresh initialization, SSH host keys changed and the `ubuntu` account became locked for password authentication.

Offline disk inspection confirmed the account state:

```text
ubuntu L ...
```

The root filesystem was mounted from the qcow2 system disk using `qemu-nbd`, the account password was restored, and the VM was started again.

Final validation confirmed:

```text
cloud-id               → nocloud
cloud-final.service     → active (exited)
cloud-init final stage  → SUCCESS
Datasource              → DataSourceNoCloud
enp1s0                  → 192.168.122.170/24
ubuntu account          → P
cloud-init errors       → []
```

The incident was resolved without reinstalling the VM or losing lab data.

---

## Environment

### Hypervisor

```text
QEMU/KVM
libvirt
```

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

Primary interface:

```text
enp1s0
```

Primary IP:

```text
192.168.122.170/24
```

Primary interface MAC:

```text
52:54:00:b0:a2:8c
```

System disk:

```text
/var/lib/libvirt/images/lab-pool/ubuntu-guest-01.qcow2
```

Secondary test disk:

```text
/var/lib/libvirt/images/lab-pool/day3-test-disk.qcow2
```

---

## Initial Cloud-init State

Cloud-init status was checked:

```bash
cloud-init status --long
```

Observed:

```text
status: disabled
extended_status: disabled
boot_status_code: disabled-by-marker-file
detail: Cloud-init disabled by /etc/cloud/cloud-init.disabled
errors: []
recoverable_errors: {}
```

The systemd unit was inspected:

```bash
systemctl status cloud-init.service --no-pager -l
```

Observed:

```text
Active: inactive (dead)
```

Cloud-init logs existed:

```bash
ls -l /var/log/cloud-init*
```

Observed files included:

```text
/var/log/cloud-init.log
/var/log/cloud-init-output.log
```

---

## Disable Marker Investigation

The marker file was inspected:

```bash
sudo ls -l /etc/cloud/cloud-init.disabled
```

Observed:

```text
-rw-r--r-- 1 root root 132 ... /etc/cloud/cloud-init.disabled
```

File metadata was inspected:

```bash
sudo stat /etc/cloud/cloud-init.disabled
```

The file was owned by:

```text
root:root
```

and had permissions:

```text
0644
```

Its contents were then inspected:

```bash
sudo cat /etc/cloud/cloud-init.disabled
```

Observed:

```text
Disabled by Ubuntu live installer after first boot.
To re-enable cloud-init on this image run:
  sudo cloud-init clean --machine-id
```

This confirmed that cloud-init had not crashed.

It had been intentionally disabled by the Ubuntu installer using a marker file.

---

## Systemd Condition Validation

The cloud-init unit was inspected:

```bash
systemctl cat cloud-init.service
```

Relevant condition:

```text
ConditionPathExists=!/etc/cloud/cloud-init.disabled
```

This means that `cloud-init.service` is allowed to run only when:

```text
/etc/cloud/cloud-init.disabled
```

does not exist.

Therefore the marker file directly explained the initial disabled state.

---

## Cloud-init Configuration Inspection

Cloud-init configuration was searched:

```bash
sudo grep -Rni "disable\|datasource" \
/etc/cloud/cloud.cfg \
/etc/cloud/cloud.cfg.d 2>/dev/null | head -n 30
```

The configuration included datasource-related settings and installer-generated configuration.

The installer network configuration was inspected:

```bash
sudo cat /etc/cloud/cloud.cfg.d/90-installer-network.cfg
```

Observed:

```yaml
network:
  ethernets:
    enp1s0:
      dhcp4: true
  version: 2
```

This matched the existing working network configuration.

---

## Cloud-init Schema Validation

The current cloud configuration was validated:

```bash
sudo cloud-init schema --system
```

Observed:

```text
Found cloud-config data types: user-data, network-config
```

User-data result:

```text
Valid schema user-data
```

Network-config result:

```text
Valid schema network-config
```

This confirmed that the existing cloud-init configuration was structurally valid before recovery work began.---

## Initial Recovery Attempt

Before changing cloud-init state, backups were created:

```bash
sudo cp /etc/cloud/cloud-init.disabled \
/root/cloud-init.disabled.inc009.bak
```

and:

```bash
sudo cp /etc/cloud/cloud.cfg.d/90-installer-network.cfg \
/root/90-installer-network.cfg.inc009.bak
```

The active network state was recorded:

```bash
ip -br addr
```

Observed:

```text
enp1s0  UP  192.168.122.170/24
enp7s0  DOWN
```

The primary interface MAC address was checked:

```bash
ip link show enp1s0
```

Observed:

```text
52:54:00:b0:a2:8c
```

The installer-supported cloud-init recovery command was then run:

```bash
sudo cloud-init clean --machine-id
```

Afterward, the disable marker was checked:

```bash
sudo ls -l /etc/cloud/cloud-init.disabled
```

Observed:

```text
ls: cannot access '/etc/cloud/cloud-init.disabled':
No such file or directory
```

This confirmed that the original installer marker had been removed.

---

## Reboot Validation

The VM was rebooted:

```bash
sudo reboot
```

After boot, cloud-init status was checked:

```bash
sudo cloud-init status --wait --long
```

Observed:

```text
status: disabled
extended_status: disabled
boot_status_code: disabled-by-generator
detail: Cloud-init disabled by cloud-init-generator
errors: []
recoverable_errors: {}
```

The marker-file issue was gone, but cloud-init still did not run.

The final cloud-init service was also inactive:

```bash
systemctl status cloud-final.service --no-pager -l
```

Observed:

```text
Active: inactive (dead)
```

This proved that removing the marker file alone was not enough to restore cloud-init.

---

## Datasource Investigation

Cloud-init generator and datasource detection state were investigated.

The datasource detection output showed:

```text
VIRT=kvm
MODE=search
ON_FOUND=all
ON_MAYBE=none
ON_NOTFOUND=disabled
```

The critical result was:

```text
No ds found [mode=search, notfound=disabled].
Disabled cloud-init
```

The VM was confirmed to be running under:

```text
KVM
```

but no cloud datasource could be detected.

The cloud identifier was checked:

```bash
sudo cloud-id
```

Observed:

```text
disabled
```

Both cloud-init startup stages were inactive:

```bash
systemctl status cloud-init-local.service --no-pager -l
```

and:

```bash
systemctl status cloud-init.service --no-pager -l
```

Observed:

```text
Active: inactive (dead)
```

---

## Root Cause

The root cause was no longer the installer marker file.

The second failure path was:

```text
Installer disable marker removed
→ cloud-init-generator started datasource detection
→ no valid datasource discovered
→ generator applied ON_NOTFOUND=disabled
→ cloud-init disabled again
```

The KVM guest did not have an external cloud metadata service.

This meant cloud-init had no datasource from which to obtain instance metadata and configuration.

---

## Existing Datasource Configuration

Configured datasource lists were inspected:

```bash
sudo grep -Rni "datasource_list" \
/etc/cloud/cloud.cfg \
/etc/cloud/cloud.cfg.d
```

The active datasource list included:

```text
NoCloud
ConfigDrive
OpenNebula
DigitalOcean
Azure
VMware
OpenStack
EC2
...
None
```

NoCloud support was therefore available.

Existing seed directories were inspected:

```bash
sudo find /var/lib/cloud/seed -maxdepth 2 -type f -print
```

No existing seed files were found.

The following paths were also checked:

```bash
sudo ls -la \
/var/lib/cloud/seed \
/var/lib/cloud/seed/nocloud \
/var/lib/cloud/seed/nocloud-net
```

Observed:

```text
/var/lib/cloud/seed/nocloud:
No such file or directory

/var/lib/cloud/seed/nocloud-net:
No such file or directory
```

This confirmed that no local NoCloud seed had been configured.

---

## NoCloud Datasource Creation

A local NoCloud datasource directory was created:

```bash
sudo mkdir -p /var/lib/cloud/seed/nocloud
```

Metadata was created:

```bash
sudo tee /var/lib/cloud/seed/nocloud/meta-data >/dev/null <<'EOF'
instance-id: inc009-kvm-001
local-hostname: lab-guest-01
EOF
```

Minimal user-data was created:

```bash
sudo tee /var/lib/cloud/seed/nocloud/user-data >/dev/null <<'EOF'
#cloud-config
preserve_hostname: true
EOF
```

Network configuration was created to preserve DHCP on the working interface:

```bash
sudo tee /var/lib/cloud/seed/nocloud/network-config >/dev/null <<'EOF'
version: 2
ethernets:
  enp1s0:
    dhcp4: true
EOF
```

The seed files were verified:

```bash
sudo find /var/lib/cloud/seed/nocloud \
-maxdepth 1 -type f -print
```

Observed:

```text
/var/lib/cloud/seed/nocloud/user-data
/var/lib/cloud/seed/nocloud/network-config
/var/lib/cloud/seed/nocloud/meta-data
```

Metadata was verified:

```text
instance-id: inc009-kvm-001
local-hostname: lab-guest-01
```

Network configuration was verified:

```yaml
version: 2
ethernets:
  enp1s0:
    dhcp4: true
```

---

## Fresh Cloud-init Run Preparation

Cloud-init state and logs were cleaned:

```bash
sudo cloud-init clean --logs
```

The NoCloud seed was checked again to ensure it remained present:

```bash
sudo find /var/lib/cloud/seed/nocloud \
-maxdepth 1 -type f -print
```

All three seed files were still present.

The VM was then rebooted to trigger a fresh cloud-init run:

```bash
sudo reboot
```---

## VM Restart Dependency Issue

After the reboot request, the VM did not return automatically.

From the WSL/libvirt host, VM state was checked:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```

Observed:

```text
shut off
```

An attempt to start the VM failed:

```bash
virsh -c qemu:///system start ubuntu-guest-01
```

Observed:

```text
Requested operation is not valid:
network 'isolated' is not active
```

The libvirt network state was inspected:

```bash
virsh -c qemu:///system net-list --all
```

Observed:

```text
default    inactive
isolated   inactive
```

The isolated network was started:

```bash
virsh -c qemu:///system net-start isolated
```

A second VM start attempt then failed with:

```text
Cannot get interface MTU on 'virbr0':
No such device
```

This showed that the default libvirt network was also required.

The default network was started:

```bash
virsh -c qemu:///system net-start default
```

Both networks were verified:

```bash
virsh -c qemu:///system net-list --all
```

Observed:

```text
default    active
isolated   active
```

The VM then started successfully:

```bash
virsh -c qemu:///system start ubuntu-guest-01
```

Validation:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```

Observed:

```text
running
```

This startup issue was separate from the cloud-init datasource problem and was caused by required libvirt networks being inactive.

---

## DHCP and Interface Verification

Direct interface address lookup initially returned no address:

```bash
virsh -c qemu:///system domifaddr ubuntu-guest-01
```

The guest interfaces were then inspected:

```bash
virsh -c qemu:///system domiflist ubuntu-guest-01
```

Observed primary NIC:

```text
MAC: 52:54:00:b0:a2:8c
Source: virbr0
Model: virtio
```

DHCP leases on the default network were checked:

```bash
virsh -c qemu:///system net-dhcp-leases default
```

Observed:

```text
MAC address: 52:54:00:b0:a2:8c
IPv4: 192.168.122.170/24
Hostname: lab-guest-01
```

This confirmed that the VM retained its expected primary address.

---

## SSH Host Key Change

After the fresh cloud-init initialization, SSH connection produced:

```text
WARNING: REMOTE HOST IDENTIFICATION HAS CHANGED!
```

The new SSH host key fingerprint differed from the previously stored key.

Because this was a controlled local VM and the system had just undergone a fresh cloud-init initialization, the stale host-key entry was removed from the WSL client:

```bash
ssh-keygen \
-f "/home/userdwara6190/.ssh/known_hosts" \
-R "192.168.122.170"
```

The new key was then accepted during the next SSH connection attempt.

In a production environment, a changed SSH host key would require independent verification before removing the old key.

---

## Authentication Failure

Although SSH reached the VM successfully, password authentication failed:

```text
Permission denied (publickey,password).
```

The known password was rejected repeatedly.

The libvirt serial console was attempted:

```bash
virsh -c qemu:///system console ubuntu-guest-01
```

The console connected but did not provide an interactive login prompt.

The QEMU guest agent was also checked:

```bash
virsh -c qemu:///system \
qemu-agent-command ubuntu-guest-01 \
'{"execute":"guest-ping"}'
```

Observed:

```text
Guest agent is not responding:
QEMU guest agent is not connected
```

This meant account recovery could not be performed through the guest agent.

---

## Offline Account Investigation

The VM system disk was identified:

```bash
virsh -c qemu:///system domblklist ubuntu-guest-01 --details
```

Observed:

```text
vda  /var/lib/libvirt/images/lab-pool/ubuntu-guest-01.qcow2
vdb  /var/lib/libvirt/images/lab-pool/day3-test-disk.qcow2
```

`vda` was confirmed as the system disk.

The VM was shut down cleanly:

```bash
virsh -c qemu:///system shutdown ubuntu-guest-01
```

State validation:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```

Observed:

```text
shut off
```

The NBD kernel module was loaded:

```bash
sudo modprobe nbd max_part=8
```

The system disk was connected:

```bash
sudo qemu-nbd \
--connect=/dev/nbd0 \
/var/lib/libvirt/images/lab-pool/ubuntu-guest-01.qcow2
```

Partition layout was inspected:

```bash
lsblk -f /dev/nbd0
```

Observed:

```text
nbd0
├─nbd0p1
├─nbd0p2                 ext4
└─nbd0p3                 LVM2_member
   └─ubuntu--vg-ubuntu--lv ext4
```

The root filesystem was mounted:

```bash
sudo mkdir -p /mnt/inc009-root
sudo mount \
/dev/mapper/ubuntu--vg-ubuntu--lv \
/mnt/inc009-root
```

The `ubuntu` account state was checked:

```bash
sudo chroot /mnt/inc009-root passwd -S ubuntu
```

Observed:

```text
ubuntu L ...
```

The corresponding shadow entry began with:

```text
!
```

This confirmed that the `ubuntu` account was locked.

---

## Offline Account Recovery

The account password was reset from the mounted root filesystem:

```bash
sudo chroot /mnt/inc009-root passwd ubuntu
```

Observed:

```text
passwd: password updated successfully
```

The account state was checked again:

```bash
sudo chroot /mnt/inc009-root passwd -S ubuntu
```

Observed:

```text
ubuntu P ...
```

The status had changed from:

```text
L
```

to:

```text
P
```

confirming that the account was now password-enabled and unlocked.

The filesystem was synchronized:

```bash
sudo sync
```

The root filesystem was unmounted:

```bash
sudo umount /mnt/inc009-root
```

The guest LVM volume was deactivated:

```bash
sudo lvchange -an ubuntu-vg/ubuntu-lv
```

The qcow2 system disk was disconnected:

```bash
sudo qemu-nbd --disconnect /dev/nbd0
```

The VM was then started again:

```bash
virsh -c qemu:///system start ubuntu-guest-01
```

and verified:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```

Observed:

```text
running
```

SSH authentication succeeded using the recovered account.

---

## Final Cloud-init Validation

Cloud-init status was checked:

```bash
sudo cloud-init status --long
```

The final output showed no cloud-init errors:

```text
errors: []
recoverable_errors: {}
```

The detected datasource was checked:

```bash
sudo cloud-id
```

Observed:

```text
nocloud
```

The final cloud-init stage was inspected:

```bash
systemctl status cloud-final.service --no-pager -l
```

Observed:

```text
Active: active (exited)
```

The process completed with:

```text
status=0/SUCCESS
```

Cloud-init logs confirmed successful datasource use:

```text
DataSourceNoCloud [seed=/var/lib/cloud/seed/nocloud]
```

and:

```text
Cloud-init ... finished ...
Datasource DataSourceNoCloud
```

The instance datasource path was also present under:

```text
/var/lib/cloud/instances/inc009-kvm-001/
```

---

## Network Validation

Guest networking was checked:

```bash
ip -br addr
```

Observed:

```text
lo      UNKNOWN  127.0.0.1/8 ::1/128
enp1s0  UP       192.168.122.170/24
enp7s0  DOWN
```

The primary network configuration therefore remained functional after cloud-init recovery.

---

## Disable Marker Validation

The original disable marker was checked again:

```bash
sudo ls -l /etc/cloud/cloud-init.disabled
```

Observed:

```text
ls: cannot access '/etc/cloud/cloud-init.disabled':
No such file or directory
```

This confirmed that cloud-init was no longer disabled by the original installer marker.

---

## Account Validation

The recovered account was checked:

```bash
passwd -S ubuntu
```

Observed:

```text
ubuntu P ...
```

This confirmed that the account remained unlocked after the VM was restarted.

---

## Final Root Cause Analysis

The incident contained two cloud-init disable conditions.

### Initial Condition

```text
/etc/cloud/cloud-init.disabled exists
→ systemd condition blocks cloud-init
→ status disabled-by-marker-file
```

The marker was intentionally created by the Ubuntu installer.

### Secondary Condition

After removing the marker:

```text
cloud-init-generator runs
→ datasource search begins
→ no datasource discovered
→ ON_NOTFOUND=disabled
→ cloud-init disabled-by-generator
```

The local KVM VM did not have an external cloud metadata datasource.

### Recovery

A valid local NoCloud datasource was added:

```text
/var/lib/cloud/seed/nocloud/
├── meta-data
├── user-data
└── network-config
```

After a fresh cloud-init initialization:

```text
Datasource → NoCloud
Final stage → SUCCESS
Network → healthy
```

A separate authentication problem was then diagnosed and recovered after the `ubuntu` account was found locked.

---

## Technical Findings

1. A cloud-init `disabled` status does not necessarily indicate a crash.
2. `/etc/cloud/cloud-init.disabled` can intentionally prevent cloud-init from running.
3. `ConditionPathExists=!/etc/cloud/cloud-init.disabled` directly controls service eligibility.
4. Removing the marker alone does not guarantee successful cloud-init startup.
5. `ds-identify` and cloud-init generator output are critical when datasource discovery fails.
6. `ON_NOTFOUND=disabled` explains why cloud-init can disable itself when no datasource exists.
7. Local KVM guests can use a NoCloud seed when no external metadata service is available.
8. `cloud-id` provides a simple validation of the active datasource.
9. `cloud-final.service` provides strong evidence that cloud-init completed its final stage.
10. Fresh initialization can affect SSH identity and authentication state and therefore requires careful post-boot validation.
11. Changed SSH host keys should never be ignored blindly in production.
12. Offline qcow2 recovery with `qemu-nbd` should only be performed while the VM is shut off.
13. System and secondary disks must be distinguished before offline modification.
14. Account state can be confirmed using `passwd -S` and `/etc/shadow`.
15. Final validation must include cloud-init status, datasource, account access, and network state.

---

## Support Troubleshooting Method

The workflow used was:

```text
Inspect service state
→ identify disable marker
→ inspect systemd conditions
→ validate configuration
→ back up critical files
→ run supported cloud-init clean
→ reboot
→ identify second disable condition
→ inspect datasource detection
→ confirm missing datasource
→ create NoCloud seed
→ clean cloud-init state
→ restart VM
→ resolve libvirt network dependencies
→ verify DHCP address
→ investigate SSH key change
→ diagnose authentication failure
→ inspect system disk offline
→ confirm locked account
→ recover account
→ detach disk safely
→ start VM
→ verify SSH
→ verify NoCloud datasource
→ verify cloud-final success
→ verify networking
→ verify account state
```

---

## Phase 3 Support Review

### Before / After Comparison

| Check | Before | After |
| --- | --- | --- |
| cloud-init status | disabled | enabled and completed |
| Initial disable reason | disabled-by-marker-file | marker absent |
| Secondary disable reason | disabled-by-generator | datasource detected |
| Datasource | none / disabled | NoCloud |
| cloud-final.service | inactive | active (exited) |
| Cloud-init errors | no successful run | errors: [] |
| Primary network | dependent on existing guest state | enp1s0 UP, 192.168.122.170/24 |
| SSH account state | ubuntu locked | ubuntu password-enabled |
| VM recovery | guest inaccessible | SSH access restored |

### Customer-Facing Symptom

A customer could describe this incident as:

```text
After attempting to re-enable cloud-init on an Ubuntu KVM VM,
cloud-init remains disabled after reboot. The VM later becomes
unreachable over SSH even though it receives its expected DHCP
address.
```

The support investigation would separate the symptom into layers:

```text
cloud-init service state
→ installer disable marker
→ datasource discovery
→ libvirt network dependencies
→ DHCP reachability
→ SSH host identity
→ account authentication state
```

### Example Support Ticket Update

```text
Status: Resolved

Cloud-init was initially disabled by the Ubuntu installer marker.
After removing the marker, cloud-init remained disabled because the
local KVM guest had no discoverable metadata datasource.

A local NoCloud datasource was configured and cloud-init completed
successfully. During validation, the VM also encountered inactive
libvirt network dependencies and a locked ubuntu account.

Both issues were recovered without reinstalling the guest.

Final validation confirmed:
- DataSourceNoCloud detected
- cloud-final.service completed successfully
- expected DHCP address restored
- SSH authentication restored
- cloud-init errors: []
```

### What I Would Do Differently

1. Capture an ISO-8601 timestamp before every major investigation and recovery step.
2. Run `cloud-init collect-logs` before modifying cloud-init state so the original evidence is preserved in one archive.
3. Verify the expected datasource before removing the installer disable marker.
4. Confirm libvirt network autostart state before rebooting the guest.
5. Record the guest SSH host-key fingerprint before a fresh cloud-init initialization.
6. Verify account state before and immediately after cloud-init recovery.
7. Prefer SSH-key authentication for recovery testing instead of relying only on a password-enabled account.

### Prevention and Operational Controls

Before re-enabling cloud-init on a persistent local VM:

```bash
cloud-init status --long
cloud-id
sudo cloud-init schema --system
sudo cloud-init collect-logs
```

Verify that the intended datasource exists before rebooting:

```bash
sudo find /var/lib/cloud/seed -maxdepth 2 -type f -print
```

For this local KVM design, verify the NoCloud seed:

```bash
sudo find /var/lib/cloud/seed/nocloud -maxdepth 1 -type f -print
```

On the libvirt host, verify network dependencies before starting the VM:

```bash
virsh -c qemu:///system net-list --all
virsh -c qemu:///system domiflist ubuntu-guest-01
```

For offline qcow2 recovery, confirm the VM is shut off before attaching the disk:

```bash
virsh -c qemu:///system domstate ubuntu-guest-01
```


### Relevant Documentation

- cloud-init documentation: disabling and enabling cloud-init
- cloud-init documentation: NoCloud datasource
- cloud-init documentation: `cloud-init clean`
- cloud-init documentation: `cloud-init collect-logs`
- Ubuntu/libvirt documentation for KVM virtual networking

---

## Final Status

```text
Initial cloud-init inspection        PASS
Disable marker identification        PASS
Systemd condition validation         PASS
Cloud-init configuration inspection  PASS
Schema validation                    PASS
Backup creation                      PASS
Marker removal                       PASS
Generator disable detection          PASS
Datasource failure diagnosis         PASS
NoCloud capability validation        PASS
NoCloud seed creation                PASS
Seed verification                    PASS
Fresh cloud-init preparation         PASS
Libvirt network recovery             PASS
VM restart                           PASS
DHCP lease validation                PASS
SSH host-key investigation           PASS
Authentication failure diagnosis     PASS
System disk identification           PASS
Offline root filesystem access       PASS
Locked account confirmation          PASS
Account recovery                     PASS
Safe disk detach                     PASS
SSH recovery                         PASS
NoCloud datasource validation        PASS
Cloud-final validation               PASS
Network validation                   PASS
Disable-marker final check           PASS
Account-state final check            PASS
```

**INC009 status: RESOLVED / VALIDATED**
