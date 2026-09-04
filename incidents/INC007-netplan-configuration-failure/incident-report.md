# INC007 — Netplan Configuration Failure

## Summary

A controlled Netplan configuration failure was reproduced on the Ubuntu guest VM.

The active network configuration was healthy and used DHCP on interface:

```text
enp1s0
```

with address:

```text
192.168.122.170/24
```

and default gateway:

```text
192.168.122.1
```

A separate test Netplan file was created with deliberately incorrect YAML indentation.

When Netplan validation was run using:

```bash
sudo netplan generate
```

Netplan rejected the file with:

```text
Invalid YAML: inconsistent indentation
```

A second issue was also detected:

```text
Permissions for /etc/netplan/99-inc007-broken.yaml are too open
```

The incident was investigated using line-numbered file inspection and permission checks.

The YAML indentation was corrected, permissions were changed to `0600`, and `netplan generate` completed successfully.

The temporary test file was then removed and the original production network configuration was revalidated.

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

Primary network interface:

```text
enp1s0
```

Secondary interface:

```text
enp7s0
```

The secondary interface remained down and was not modified during this incident.

---

## Network Baseline

Interface state was checked:

```bash
ip -br addr
```

Observed:

```text
lo      UNKNOWN  127.0.0.1/8 ::1/128
enp1s0  UP       192.168.122.170/24
enp7s0  DOWN
```

Routing was checked:

```bash
ip route
```

Observed:

```text
default via 192.168.122.1 dev enp1s0
192.168.122.0/24 dev enp1s0
192.168.122.1 dev enp1s0
```

The active Netplan directory was inspected:

```bash
ls -l /etc/netplan
```

Observed active file:

```text
50-cloud-init.yaml
```

---

## Existing Netplan Configuration

The production configuration was inspected:

```bash
sudo cat /etc/netplan/50-cloud-init.yaml
```

Observed:

```yaml
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true
```

This confirmed that `enp1s0` was using DHCP.

A backup was created before testing:

```bash
sudo cp /etc/netplan/50-cloud-init.yaml \
/etc/netplan/50-cloud-init.yaml.backup-inc007
```

The backup was verified with:

```bash
ls -l /etc/netplan/
```---

## Controlled Failure Creation

A separate test Netplan file was created so the working production configuration would remain untouched.

The test file was created as:

```bash
sudo tee /etc/netplan/99-inc007-broken.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true
     addresses:
        - 10.10.10.10/24
EOF
```

The indentation before:

```text
addresses:
```

was deliberately incorrect.

No `netplan apply` command was used.

This ensured the SSH session and active network path would not be disrupted.

---

## Failure Reproduction

Netplan configuration generation was attempted:

```bash
sudo netplan generate
```

Netplan rejected the file.

Observed warning:

```text
Permissions for /etc/netplan/99-inc007-broken.yaml are too open.
Netplan configuration should NOT be accessible by others.
```

Observed YAML error:

```text
/etc/netplan/99-inc007-broken.yaml:6:6:
Invalid YAML: inconsistent indentation:
     addresses:
     ^
```

This confirmed that the configuration could not be parsed.

---

## Configuration Investigation

The broken file was displayed with line numbers:

```bash
sudo nl -ba /etc/netplan/99-inc007-broken.yaml
```

Observed:

```text
1  network:
2    version: 2
3    ethernets:
4      enp1s0:
5        dhcp4: true
6       addresses:
7          - 10.10.10.10/24
```

Line 6 was incorrectly aligned relative to the other settings under `enp1s0`.

The file permissions were checked:

```bash
ls -l /etc/netplan/99-inc007-broken.yaml
```

Observed:

```text
-rw-r--r-- 1 root root ... /etc/netplan/99-inc007-broken.yaml
```

The file therefore had permissions equivalent to:

```text
0644
```

This matched the Netplan permissions warning.

---

## Root Cause

Two configuration defects were identified.

### Primary Failure

```text
Invalid YAML indentation
```

The `addresses:` key was not aligned correctly under the `enp1s0` interface definition.

### Secondary Issue

```text
Netplan file permissions too open
```

The test configuration was readable by users other than root.

The combined incident state was:

```text
Incorrect YAML indentation
→ netplan generate rejected configuration

Permissions 0644
→ Netplan security warning
```---

## Recovery

The test Netplan configuration was rewritten with valid indentation:

```bash
sudo tee /etc/netplan/99-inc007-broken.yaml >/dev/null <<'EOF'
network:
  version: 2
  ethernets:
    enp1s0:
      dhcp4: true
      addresses:
        - 10.10.10.10/24
EOF
```

The file permissions were then restricted:

```bash
sudo chmod 600 /etc/netplan/99-inc007-broken.yaml
```

The corrected file was inspected with line numbers:

```bash
sudo nl -ba /etc/netplan/99-inc007-broken.yaml
```

Observed:

```text
1  network:
2    version: 2
3    ethernets:
4      enp1s0:
5        dhcp4: true
6        addresses:
7          - 10.10.10.10/24
```

The file permissions were checked again:

```bash
ls -l /etc/netplan/99-inc007-broken.yaml
```

Observed:

```text
-rw------- 1 root root ... /etc/netplan/99-inc007-broken.yaml
```

The permissions were now equivalent to:

```text
0600
```

---

## Recovery Validation

Netplan configuration generation was run again:

```bash
sudo netplan generate
```

Result:

```text
No error output
No permission warning
```

This confirmed that:

```text
YAML syntax        PASS
File permissions   PASS
Netplan generation PASS
```

No `netplan apply` command was used because the objective was to validate configuration parsing without risking the active SSH network path.

---

## Cleanup

The temporary test configuration was removed:

```bash
sudo rm /etc/netplan/99-inc007-broken.yaml
```

The production Netplan configuration was validated again:

```bash
sudo netplan generate
```

The command completed without errors.

---

## Network Post-Validation

Interface state was checked:

```bash
ip -br addr
```

Observed:

```text
enp1s0  UP    192.168.122.170/24
enp7s0  DOWN
```

The routing table was checked:

```bash
ip route
```

Observed:

```text
default via 192.168.122.1 dev enp1s0
192.168.122.0/24 dev enp1s0
192.168.122.1 dev enp1s0
```

Gateway connectivity was tested:

```bash
ping -c 4 192.168.122.1
```

Result:

```text
4 packets transmitted
4 received
0% packet loss
```

This confirmed that the production network configuration remained healthy after the incident exercise.

---

## Result

The Netplan configuration failure was successfully diagnosed and resolved.

Failure path:

```text
Broken YAML indentation
→ netplan generate failed
→ invalid configuration identified
```

Secondary issue:

```text
Permissions 0644
→ Netplan security warning
```

Recovery path:

```text
Inspect line numbers
→ identify indentation defect
→ inspect permissions
→ correct YAML
→ chmod 600
→ rerun netplan generate
→ validation succeeds
→ remove test config
→ revalidate production network
```

---

## Technical Findings

1. YAML indentation errors can prevent Netplan from generating network configuration.
2. `netplan generate` is useful for validating configuration before applying changes.
3. Network configuration should not be applied until syntax validation succeeds.
4. Line-numbered inspection using `nl -ba` helps identify exact YAML alignment problems.
5. Netplan files should not be unnecessarily readable by other users.
6. Permissions of `0600` removed the Netplan warning in this test.
7. A working configuration should be backed up before changes are introduced.
8. Network recovery validation should include interface state, routing, and gateway connectivity.
9. `netplan apply` should be avoided during troubleshooting until configuration validation passes.
10. Temporary test configuration should be removed after the incident is complete.

---

## Support Troubleshooting Method

The workflow used was:

```text
Baseline
→ Backup
→ Introduce controlled config defect
→ Validate
→ Read exact error
→ Inspect line numbers
→ Inspect permissions
→ Correct configuration
→ Validate again
→ Cleanup
→ Verify network state
→ Verify routing
→ Verify connectivity
```

This approach reduces the risk of turning a configuration error into an actual network outage.

---

## Final Status

```text
Network baseline                  PASS
Existing Netplan inspection       PASS
Configuration backup              PASS
Controlled YAML failure           PASS
Netplan error reproduction        PASS
Permission warning identification PASS
Line-level investigation          PASS
YAML correction                   PASS
Permission correction             PASS
Netplan generation validation     PASS
Temporary config cleanup          PASS
Production config validation      PASS
Interface-state validation        PASS
Route validation                  PASS
Gateway connectivity              PASS
```

**INC007 status: RESOLVED / VALIDATED**
