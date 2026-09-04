# INC013 — Snap Strict Confinement Failure and Diagnostic Validation

## Summary

A controlled Snap confinement failure was reproduced and validated on the Ubuntu KVM guest.

The Snap environment was checked first.

Observed baseline:

```text
snap                     → installed
snap version             → 2.76
snapd.socket             → active
snapd.apparmor.service   → active
confinement              → strict
installed snaps          → none
```

Although `snapd.service` was initially inactive, this was not a failure because Snap was operating through socket activation.

The Snap socket was confirmed as:

```text
Active: active (listening)
```

and `snap changes` responded successfully.

The `hello-world` snap was then installed in normal strict mode.

Its state showed:

```text
confinement: strict
devmode: false
```

The normal command:

```bash
hello-world
```

worked successfully:

```text
Hello World!
```

The confinement test command:

```bash
hello-world.evil
```

attempted to create:

```text
/var/tmp/myevil.txt
```

and failed with:

```text
Permission denied
```

The command exited with:

```text
exit_code=2
```

Kernel audit logs provided direct AppArmor evidence:

```text
apparmor="DENIED"
profile="snap.hello-world.evil"
name="/var/tmp/myevil.txt"
requested_mask="c"
denied_mask="c"
```

The same snap was then reinstalled temporarily using:

```text
--devmode
```

The application state showed:

```text
confinement: strict
devmode: true
```

The exact same command:

```bash
hello-world.evil
```

then completed successfully with:

```text
exit_code=0
```

and created:

```text
/var/tmp/myevil.txt
```

This A/B comparison proved that the failure was caused by confinement enforcement rather than by:

```text
Snap installation failure
application corruption
filesystem absence
command failure
snapd outage
```

After validation, the devmode snap and test file were removed.

Final state:

```text
hello-world snap        → removed
/var/tmp/myevil.txt     → removed
snapd.socket            → active
snapd.apparmor.service  → active
confinement             → strict
```

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

## Initial Snap Availability Check

Snap availability was checked:

```bash
command -v snap || echo "snap not installed"
```

Observed:

```text
/usr/bin/snap
```

This confirmed the Snap client was installed.

---

## snapd Service Observation

The snapd service was checked:

```bash
systemctl is-active snapd || echo "snapd not active"
```

Observed:

```text
inactive
snapd not active
```

This initially appeared suspicious, but further investigation was required before treating it as a failure.

---

## Snap Version

The Snap version was checked:

```bash
snap version
```

Observed:

```text
snap    2.76+ubuntu24.04.1
snapd   2.76+ubuntu24.04.1
series  16
ubuntu  24.04
kernel  6.8.0-139-generic
architecture amd64
```

This confirmed that Snap components were installed correctly.

---

## Installed Snap Baseline

Installed snaps were checked:

```bash
snap list
```

Observed:

```text
No snaps are installed yet.
```

This provided a clean baseline before INC013.

---

## Confinement Capability

Snap confinement support was checked:

```bash
snap debug confinement
```

Observed:

```text
strict
```

This confirmed the system supported strict Snap confinement.

---

## snapd Socket Validation

Because `snapd.service` was inactive, the Snap socket was inspected:

```bash
systemctl status snapd.socket --no-pager -l
```

Observed:

```text
Active: active (listening)
```

The socket was listening on:

```text
/run/snapd.socket
/run/snapd-snap.socket
```

The socket state was also checked directly:

```bash
systemctl is-active snapd.socket
```

Observed:

```text
active
```

This confirmed that snapd was available through socket activation.

---

## Snap AppArmor Integration

The Snap-managed AppArmor service was checked:

```bash
systemctl status snapd.apparmor.service --no-pager -l
```

Observed:

```text
Active: active (exited)
```

The service description confirmed:

```text
Load AppArmor profiles managed internally by snapd
```

This proved that Snap's AppArmor integration was operational.

---

## Snap API Validation

Snap responsiveness was checked:

```bash
snap changes
```

Observed:

```text
ID  Status  Spawn                 Ready                 Summary
1   Done    yesterday at 15:55 UTC yesterday at 15:55 UTC Initialize system state
```

This confirmed that Snap was functioning despite `snapd.service` being inactive.

The correct baseline interpretation was therefore:

```text
snapd.service inactive
≠
Snap unavailable
```

because:

```text
snapd.socket → active
Snap API      → responsive
```

---

## Test Snap Installation

The `hello-world` snap was installed:

```bash
sudo snap install hello-world
```

Observed:

```text
hello-world 6.4 from Canonical installed
```

The installation completed successfully.

---

## Installed Snap Validation

The installed snap was checked:

```bash
snap list hello-world
```

Observed:

```text
Name         Version  Rev  Tracking       Publisher   Notes
hello-world  6.4      29   latest/stable  canonical   -
```

---

## Strict Confinement Validation

The snap metadata was inspected:

```bash
snap info --verbose hello-world | \
grep -E 'confinement|devmode'
```

Observed:

```text
confinement: strict
devmode:     false
```

This established the secure baseline:

```text
Strict confinement enabled
Devmode disabled
```

---

## Normal Application Baseline

The normal snap command was executed:

```bash
hello-world
```

Observed:

```text
Hello World!
```

This proved the application itself was installed and executable.

The baseline state was therefore:

```text
Snap installed      → yes
Normal command      → works
Strict confinement  → enabled
AppArmor integration→ active
```

---

## Controlled Confinement Failure

The confinement demonstration command was executed:

```bash
hello-world.evil
```

Observed:

```text
Hello Evil World!
This example demonstrates the app confinement
You should see a permission denied error next
/snap/hello-world/29/bin/evil: 9:
/snap/hello-world/29/bin/evil:
cannot create /var/tmp/myevil.txt: Permission denied
```

The exit code was checked immediately:

```bash
echo "exit_code=$?"
```

Observed:

```text
exit_code=2
```

This confirmed a real execution failure.

---

## Kernel AppArmor Evidence

Kernel logs were inspected:

```bash
sudo journalctl -k \
--since "2 minutes ago" \
--no-pager | \
grep -Ei 'apparmor="DENIED"|snap\.hello-world' | \
tail -n 20
```

Observed audit evidence included:

```text
apparmor="DENIED"
operation="mknod"
profile="snap.hello-world.evil"
name="/var/tmp/myevil.txt"
requested_mask="c"
denied_mask="c"
```

This was direct kernel-level evidence that AppArmor enforcement blocked the snap from creating the file.

---

## Failure State

During the strict confinement failure:

```text
snap                    → installed
snapd socket            → active
Snap AppArmor service   → active
hello-world             → works
hello-world.evil        → fails
exit code               → 2
target file             → blocked
kernel                  → AppArmor DENIED
```

This showed that the failure was not a platform outage.

The failure was caused specifically by the security policy applied to the confined application.---

## Diagnostic Devmode Comparison

To prove that confinement enforcement was the cause of the failure, the strict installation was removed:

```bash
sudo snap remove hello-world
```

Observed:

```text
hello-world removed (snap data snapshot saved)
```

The same snap was then reinstalled temporarily in devmode:

```bash
sudo snap install hello-world --devmode
```

Observed:

```text
hello-world 6.4 from Canonical installed
```

---

## Devmode Validation

The snap installation state was checked:

```bash
snap list hello-world
```

Observed:

```text
Name         Version  Rev  Tracking       Publisher   Notes
hello-world  6.4      29   latest/stable  canonical   devmode
```

The confinement metadata was inspected:

```bash
snap info --verbose hello-world | \
grep -E 'confinement|devmode'
```

Observed:

```text
confinement: strict
devmode:     true
```

This confirmed that the snap still declared strict confinement, but enforcement was relaxed for diagnostic purposes.

---

## Same Command in Devmode

The exact same command was executed again:

```bash
hello-world.evil
```

Observed:

```text
Hello Evil World!
This example demonstrates the app confinement
You should see a permission denied error next
If you see this line the confinement is not working correctly, please file a bug
```

Unlike strict mode, the command completed successfully.

The exit code was checked:

```bash
echo "exit_code=$?"
```

Observed:

```text
exit_code=0
```

This was materially different from strict mode:

```text
Strict mode  → exit_code=2
Devmode      → exit_code=0
```

---

## File Creation Validation

The target file was checked:

```bash
sudo ls -l /var/tmp/myevil.txt
```

Observed:

```text
-rw-rw-r-- 1 ubuntu ubuntu 5 Sep 4 16:45 /var/tmp/myevil.txt
```

This proved that the same operation which was blocked in strict mode succeeded in devmode.

---

## A/B Comparison

### Strict Mode

```text
confinement       → strict
devmode           → false
hello-world       → works
hello-world.evil  → Permission denied
exit code         → 2
target file       → blocked
AppArmor log      → DENIED
```

### Devmode

```text
confinement       → strict
devmode           → true
hello-world.evil  → succeeds
exit code         → 0
target file       → created
```

The environment, snap revision, command, and target path remained effectively the same.

The key changed condition was:

```text
confinement enforcement
```

This provided strong causal evidence.

---

## Root Cause

The root cause was Snap strict confinement enforced through AppArmor.

The command attempted to create:

```text
/var/tmp/myevil.txt
```

while running under the AppArmor profile:

```text
snap.hello-world.evil
```

The kernel denied the requested create operation.

Failure chain:

```text
hello-world.evil starts
→ snap executes under strict confinement
→ process attempts to create /var/tmp/myevil.txt
→ AppArmor evaluates snap profile
→ requested create access is denied
→ shell reports Permission denied
→ command exits with code 2
```

The application binary itself was functional.

The platform itself was also functional.

The failure was an intentional security enforcement event.

---

## Why snapd.service Being Inactive Was Not the Root Cause

At the start of the investigation:

```text
snapd.service → inactive
```

However:

```text
snapd.socket           → active
snap commands          → responsive
snap installation      → successful
strict confinement     → available
AppArmor integration   → active
```

Therefore, treating the inactive daemon service as the primary fault would have been incorrect.

The correct interpretation was:

```text
snapd is socket-activated
```

and the actual incident was unrelated to daemon availability.

---

## Snap Interface Observation

Snap connections were inspected:

```bash
snap connections hello-world
```

No connection output was shown for the test snap.

This did not affect the confinement demonstration because the observed failure was directly evidenced by:

```text
AppArmor DENIED
```

against the snap's security profile.

---

## Diagnostic Meaning of Devmode

Devmode was used only to isolate the cause of the failure.

It was not treated as the production fix.

The diagnostic logic was:

```text
Strict mode blocks operation
→ Devmode allows same operation
→ filesystem path is valid
→ executable is valid
→ Snap installation is valid
→ denial is caused by confinement policy
```

Leaving the application permanently in devmode would weaken confinement and would not represent a secure final state.

---

## Cleanup

After the diagnostic comparison, the devmode snap was removed:

```bash
sudo snap remove hello-world
```

Observed:

```text
hello-world removed (snap data snapshot saved)
```

The test file was removed:

```bash
sudo rm -f /var/tmp/myevil.txt
```

---

## Snap Removal Validation

The snap was checked:

```bash
snap list hello-world 2>&1 || true
```

Observed:

```text
error: no matching snaps installed
```

This confirmed the temporary snap had been removed.

---

## Test File Cleanup Validation

The test file was checked:

```bash
sudo ls -l /var/tmp/myevil.txt 2>&1 || true
```

Observed:

```text
ls: cannot access '/var/tmp/myevil.txt': No such file or directory
```

This confirmed that the temporary file created during devmode testing had been removed.

---

## Final Snap Security Validation

The Snap socket was checked:

```bash
systemctl is-active snapd.socket
```

Observed:

```text
active
```

The Snap AppArmor integration service was checked:

```bash
systemctl is-active snapd.apparmor.service
```

Observed:

```text
active
```

Confinement capability was checked again:

```bash
snap debug confinement
```

Observed:

```text
strict
```

The base Snap security environment therefore remained healthy after cleanup.

---

## Final State

Temporary incident artifacts:

```text
hello-world snap       → removed
/var/tmp/myevil.txt    → removed
```

Persistent Snap infrastructure:

```text
snap                   → installed
snapd.socket           → active
snapd.apparmor.service → active
confinement            → strict
```

The VM was returned to a secure baseline.

---

## Technical Findings

1. `snapd.service` being inactive does not necessarily indicate a Snap outage because snapd can operate through socket activation.
2. `snapd.socket` should be checked before diagnosing daemon availability.
3. `snap debug confinement` provides a direct check of the available confinement mode.
4. A snap can be installed correctly and still be denied access to a host resource by policy.
5. Application success and confinement success are separate questions.
6. Kernel AppArmor audit logs provide stronger root-cause evidence than a generic permission error alone.
7. The AppArmor profile name identifies the confined snap command involved in the denial.
8. Comparing strict mode against devmode is useful for isolating confinement as the cause.
9. Devmode is a diagnostic mechanism, not a secure permanent fix.
10. The same command succeeding in devmode proves the target path and application logic are usable.
11. Security controls should not be disabled permanently simply to make an application work.
12. Controlled security testing should include cleanup of temporary snaps and created files.
13. Final validation should confirm that strict confinement remains available after testing.
14. Security-policy incidents require distinguishing intended enforcement from platform failure.

---

## Support Troubleshooting Method

The workflow used was:

```text
Check Snap client availability
→ inspect snapd service state
→ inspect Snap version
→ inspect installed snaps
→ confirm strict confinement capability
→ inspect snapd socket
→ confirm socket activation
→ inspect Snap AppArmor service
→ validate Snap API responsiveness
→ install test snap
→ verify strict confinement
→ validate normal command
→ reproduce restricted operation
→ capture exit code
→ capture kernel AppArmor denial
→ inspect snap connections
→ remove strict installation
→ reinstall same snap in devmode
→ verify devmode state
→ rerun exact same command
→ confirm successful execution
→ confirm target file creation
→ compare strict and devmode behavior
→ identify confinement as root cause
→ remove devmode snap
→ remove test file
→ verify temporary artifacts removed
→ verify snapd socket
→ verify AppArmor integration
→ verify strict confinement remains available
```

---

## Final Status

```text
Snap client availability              PASS
Snap version validation               PASS
Initial snap baseline                 PASS
Strict confinement capability         PASS
snapd socket validation               PASS
Snap AppArmor integration             PASS
Snap API responsiveness               PASS
hello-world installation              PASS
Strict mode validation                PASS
Normal application execution          PASS
Controlled confinement failure        PASS
Permission denial validation          PASS
Exit code validation                  PASS
Kernel AppArmor evidence              PASS
Security profile identification       PASS
Root cause identification             PASS
Strict snap removal                   PASS
Devmode installation                  PASS
Devmode state validation              PASS
Same-command diagnostic comparison    PASS
Devmode execution validation          PASS
Target file creation validation       PASS
Confinement causality validation      PASS
Devmode snap cleanup                  PASS
Test file cleanup                     PASS
Snap removal validation               PASS
File removal validation               PASS
snapd socket final validation         PASS
AppArmor final validation             PASS
Strict confinement final validation   PASS
```

**INC013 status: RESOLVED / VALIDATED**
