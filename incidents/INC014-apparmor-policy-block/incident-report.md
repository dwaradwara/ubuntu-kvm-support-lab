# INC014 — AppArmor Policy Blocking and Least-Privilege Recovery

## Summary

A controlled AppArmor policy failure was reproduced and recovered on the Ubuntu KVM guest.

The AppArmor environment was validated first.

Observed baseline:

```text
AppArmor service          → active
Kernel AppArmor support   → enabled
apparmor_parser           → available
aa-exec                   → available
aa-status                 → available
/etc/apparmor.d           → present
```

A dedicated test executable was created:

```text
/usr/local/bin/inc014-reader
```

Two test files were created:

```text
/tmp/inc014-allowed.txt
/tmp/inc014-secret.txt
```

Before applying any AppArmor profile, the test executable could read both files successfully:

```text
INC014 allowed data
INC014 restricted data
```

A custom AppArmor profile named:

```text
inc014-reader
```

was then created and loaded.

The initial policy allowed access to:

```text
/tmp/inc014-allowed.txt
```

but did not permit access to:

```text
/tmp/inc014-secret.txt
```

After the profile was enforced:

```text
allowed file     → readable
restricted file  → Permission denied
exit code        → 1
```

Kernel audit logs confirmed the denial:

```text
apparmor="DENIED"
profile="inc014-reader"
name="/tmp/inc014-secret.txt"
requested_mask="r"
denied_mask="r"
```

The incident was recovered by updating the AppArmor profile to explicitly allow read access to the restricted file.

After the corrected policy was reloaded:

```text
allowed file     → readable
restricted file  → readable
profile          → still enforced
```

The fix therefore preserved AppArmor enforcement instead of disabling the security control.

After validation, the custom profile, executable, and test files were removed.

Final state:

```text
INC014 profile             → removed
INC014 test executable     → removed
INC014 test files          → removed
AppArmor service           → active
Kernel AppArmor support    → enabled
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

## Initial AppArmor Baseline

AppArmor state was inspected before creating the incident.

The loaded profile state was checked with:

```bash
sudo aa-status
```

The system showed loaded AppArmor profiles and at least one process operating under enforce mode.

This confirmed that AppArmor was already active on the guest.

---

## AppArmor Parser Availability

The AppArmor parser was checked:

```bash
command -v apparmor_parser || \
echo "apparmor_parser not installed"
```

Observed:

```text
/usr/sbin/apparmor_parser
```

This confirmed that custom profiles could be parsed and loaded.

---

## AppArmor Profile Directory

The standard profile directory was checked:

```bash
ls -ld /etc/apparmor.d
```

Observed:

```text
/etc/apparmor.d
```

The directory existed and was available for the INC014 custom profile.

---

## Kernel AppArmor Support

Kernel AppArmor support was checked:

```bash
cat /sys/module/apparmor/parameters/enabled
```

Observed:

```text
Y
```

This confirmed that AppArmor was enabled at the kernel level.

---

## AppArmor Helper Tools

The AppArmor execution helper was checked:

```bash
command -v aa-exec || \
echo "aa-exec not installed"
```

Observed:

```text
/usr/bin/aa-exec
```

The status command was also available:

```bash
command -v aa-status
```

Observed:

```text
/usr/sbin/aa-status
```

This confirmed that the guest had the tooling required for profile validation and inspection.

---

## Test Data Creation

Two controlled files were created.

Allowed test data:

```bash
echo "INC014 allowed data" | \
sudo tee /tmp/inc014-allowed.txt
```

Observed:

```text
INC014 allowed data
```

Restricted test data:

```bash
echo "INC014 restricted data" | \
sudo tee /tmp/inc014-secret.txt
```

Observed:

```text
INC014 restricted data
```

---

## Test Executable Creation

A dedicated reader executable was created by copying `/usr/bin/cat`:

```bash
sudo cp \
/usr/bin/cat \
/usr/local/bin/inc014-reader
```

The executable permission was set:

```bash
sudo chmod 755 \
/usr/local/bin/inc014-reader
```

This created a predictable executable path for the AppArmor profile:

```text
/usr/local/bin/inc014-reader
```

---

## Pre-Policy Functional Baseline

Before any AppArmor profile was applied, the reader was tested against the allowed file:

```bash
/usr/local/bin/inc014-reader \
/tmp/inc014-allowed.txt
```

Observed:

```text
INC014 allowed data
```

The same executable was then tested against the restricted file:

```bash
/usr/local/bin/inc014-reader \
/tmp/inc014-secret.txt
```

Observed:

```text
INC014 restricted data
```

This established the critical pre-policy baseline:

```text
Executable works
Allowed file readable
Restricted file readable
No application-level failure
```

---

## Custom AppArmor Profile Creation

A dedicated AppArmor profile was created:

```text
/etc/apparmor.d/usr.local.bin.inc014-reader
```

Profile content:

```text
#include <tunables/global>

profile inc014-reader /usr/local/bin/inc014-reader {
  #include <abstractions/base>

  /usr/local/bin/inc014-reader mr,
  /tmp/inc014-allowed.txt r,
}
```

The policy granted:

```text
read access → /tmp/inc014-allowed.txt
```

but did not grant:

```text
read access → /tmp/inc014-secret.txt
```

Because AppArmor follows allow-list policy behavior, the missing permission was sufficient to block access.

---

## Profile Syntax Validation

The custom profile was checked before loading:

```bash
sudo apparmor_parser -Q \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

No error output was returned.

This confirmed valid profile syntax.

---

## Profile Load

The profile was loaded:

```bash
sudo apparmor_parser -r \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

The profile state was then checked:

```bash
sudo aa-status | grep -F inc014-reader
```

Observed:

```text
inc014-reader
```

This confirmed that the custom profile was loaded and enforced.

---

## Allowed Access Validation

The file explicitly allowed by policy was tested again:

```bash
/usr/local/bin/inc014-reader \
/tmp/inc014-allowed.txt
```

Observed:

```text
INC014 allowed data
```

This showed that the profile did not break all application behavior.

The configured allowed path continued to work correctly.

---

## Controlled AppArmor Failure

The same executable was then used against the restricted path:

```bash
/usr/local/bin/inc014-reader \
/tmp/inc014-secret.txt
```

Observed:

```text
/usr/local/bin/inc014-reader:
/tmp/inc014-secret.txt:
Permission denied
```

The exit code was captured:

```bash
rc=$?
echo "exit_code=$rc"
```

Observed:

```text
exit_code=1
```

This confirmed an actual application-level failure after the AppArmor profile was enforced.

---

## Kernel Audit Evidence

Kernel logs were inspected:

```bash
sudo journalctl -k \
--since "2 minutes ago" \
--no-pager | \
grep -Ei \
'apparmor="DENIED"|inc014-reader|inc014-secret' | \
tail -n 20
```

The audit output included:

```text
apparmor="DENIED"
operation="open"
class="file"
profile="inc014-reader"
name="/tmp/inc014-secret.txt"
requested_mask="r"
denied_mask="r"
```

This provided direct kernel-level evidence that AppArmor caused the read failure.

---

## Failure State

During the incident:

```text
AppArmor service          → active
AppArmor kernel support   → enabled
Custom profile            → loaded
Reader executable         → functional
Allowed file              → readable
Restricted file           → blocked
Exit code                 → 1
Kernel audit              → AppArmor DENIED
```

The failure was therefore isolated to the access-control policy rather than the executable or file itself.
---

## Policy Correction

The root cause was the missing AppArmor read permission for:

```text
/tmp/inc014-secret.txt
```

The custom profile was edited:

```bash
sudo nano \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

The required rule was added:

```text
/tmp/inc014-secret.txt r,
```

The corrected profile became:

```text
#include <tunables/global>

profile inc014-reader /usr/local/bin/inc014-reader {
  #include <abstractions/base>

  /usr/local/bin/inc014-reader mr,
  /tmp/inc014-allowed.txt r,
  /tmp/inc014-secret.txt r,
}
```

This preserved the existing policy structure while granting only the access required by the application.

---

## Corrected Profile Validation

The updated profile syntax was checked:

```bash
sudo apparmor_parser -Q \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

No error output was returned.

This confirmed the corrected policy was syntactically valid.

---

## Corrected Profile Reload

The updated profile was reloaded:

```bash
sudo apparmor_parser -r \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

The profile remained loaded under AppArmor.

This was important because recovery was performed by correcting policy rather than unloading the profile or disabling AppArmor.

---

## Allowed File Recovery Validation

The original allowed path was tested again:

```bash
/usr/local/bin/inc014-reader \
/tmp/inc014-allowed.txt
```

Observed:

```text
INC014 allowed data
```

This confirmed that the existing allowed behavior remained functional after the policy update.

---

## Restricted File Recovery Validation

The previously blocked file was tested again:

```bash
/usr/local/bin/inc014-reader \
/tmp/inc014-secret.txt
```

Observed:

```text
INC014 restricted data
```

This proved that the application could now access the required file.

---

## Profile Enforcement After Recovery

The custom profile was checked again:

```bash
sudo aa-status | grep -F inc014-reader
```

Observed:

```text
inc014-reader
```

This confirmed:

```text
AppArmor profile → still loaded
Required access  → restored
Security control → still enabled
```

The recovery therefore did not rely on disabling enforcement.

---

## Before / During / After Comparison

### Before AppArmor Profile

```text
inc014-reader              → functional
inc014-allowed.txt         → readable
inc014-secret.txt          → readable
AppArmor custom policy     → not loaded
```

### During Failure

```text
inc014-reader              → functional
Custom profile             → loaded
inc014-allowed.txt         → readable
inc014-secret.txt          → Permission denied
Exit code                  → 1
Kernel audit               → AppArmor DENIED
```

### After Policy Correction

```text
Custom profile             → still loaded
inc014-allowed.txt         → readable
inc014-secret.txt          → readable
AppArmor enforcement       → preserved
```

This provided a complete:

```text
working
→ policy-induced failure
→ policy-corrected recovery
```

lifecycle.

---

## Root Cause

The application failure was caused by an incomplete AppArmor allow-list policy.

The original profile allowed:

```text
/tmp/inc014-allowed.txt r,
```

but contained no read permission for:

```text
/tmp/inc014-secret.txt
```

The application attempted to open the restricted file.

AppArmor evaluated the request against:

```text
profile="inc014-reader"
```

and denied the requested read operation.

Failure chain:

```text
inc014-reader starts
→ AppArmor applies inc014-reader profile
→ application requests read access to /tmp/inc014-secret.txt
→ profile contains no matching read permission
→ AppArmor denies open operation
→ application receives Permission denied
→ command exits with code 1
```

The failure was therefore caused by:

```text
Missing AppArmor file-read permission
```

rather than:

```text
Missing file
Invalid UNIX permissions
Broken executable
AppArmor service failure
Kernel failure
```

---

## Why Disabling AppArmor Was Not the Correct Fix

A simple workaround would have been to unload the profile or disable AppArmor.

That would have removed the symptom, but it would also have removed the intended security control.

Instead, the profile was corrected with the minimum required permission:

```text
/tmp/inc014-secret.txt r,
```

This preserved:

```text
AppArmor enforcement
Application functionality
Least-privilege policy design
```

The recovery therefore addressed the actual policy defect.

---

## Cleanup

After recovery was validated, the temporary INC014 profile was unloaded:

```bash
sudo apparmor_parser -R \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

The profile file was removed:

```bash
sudo rm \
/etc/apparmor.d/usr.local.bin.inc014-reader
```

The temporary reader executable was removed:

```bash
sudo rm \
/usr/local/bin/inc014-reader
```

The test files were removed:

```bash
sudo rm -f \
/tmp/inc014-allowed.txt \
/tmp/inc014-secret.txt
```

---

## Profile Cleanup Validation

The temporary profile was checked:

```bash
sudo aa-status | \
grep -F inc014-reader || \
echo "INC014 profile removed"
```

Observed:

```text
INC014 profile removed
```

This confirmed that the temporary custom policy had been unloaded successfully.

---

## Executable Cleanup Validation

The test executable was checked:

```bash
ls -l /usr/local/bin/inc014-reader \
2>&1 || true
```

Observed:

```text
ls: cannot access '/usr/local/bin/inc014-reader':
No such file or directory
```

This confirmed that the test executable had been removed.

---

## Test File Cleanup Validation

The test files were checked:

```bash
ls -l \
/tmp/inc014-allowed.txt \
/tmp/inc014-secret.txt \
2>&1 || true
```

Observed:

```text
ls: cannot access '/tmp/inc014-allowed.txt':
No such file or directory

ls: cannot access '/tmp/inc014-secret.txt':
No such file or directory
```

This confirmed that the temporary test data had been removed.

---

## Final AppArmor Health Validation

The AppArmor service was checked:

```bash
systemctl is-active apparmor
```

Observed:

```text
active
```

Kernel AppArmor support was checked:

```bash
cat /sys/module/apparmor/parameters/enabled
```

Observed:

```text
Y
```

This confirmed that cleanup removed only the INC014 test artifacts and did not disable AppArmor.

---

## Final State

Temporary INC014 resources:

```text
Custom profile         → removed
Test executable        → removed
Allowed test file      → removed
Restricted test file   → removed
```

Persistent AppArmor state:

```text
AppArmor service       → active
Kernel support         → enabled
```

The VM was returned to a clean secure baseline.

---

## Technical Findings

1. An application can fail with `Permission denied` even when the file exists and normal UNIX permissions are valid.
2. AppArmor denials should be confirmed with kernel audit logs rather than inferred from the application error alone.
3. The AppArmor profile name identifies which security policy was applied to the process.
4. `requested_mask` and `denied_mask` provide direct evidence of the blocked operation.
5. Allow-list profiles deny access that is not explicitly permitted.
6. A security-policy failure does not imply that AppArmor itself is malfunctioning.
7. A working executable before profile load helps isolate the problem to policy enforcement.
8. Testing an allowed and restricted path side by side is useful for proving selective policy behavior.
9. Reloading a corrected profile is preferable to disabling AppArmor.
10. The correct fix should grant only the access actually required.
11. AppArmor policy syntax should be validated before loading or reloading a profile.
12. Recovery should confirm that the profile remains enforced.
13. Security controls should not be removed merely to restore application functionality.
14. Cleanup should remove temporary profiles and test artifacts while preserving the host security framework.
15. Comparing pre-policy, failure, and corrected-policy states provides strong root-cause evidence.

---

## Support Troubleshooting Method

The workflow used was:

```text
Validate AppArmor service
→ validate kernel AppArmor support
→ confirm AppArmor tooling
→ create controlled test files
→ create dedicated test executable
→ confirm unrestricted baseline access
→ create custom AppArmor profile
→ validate profile syntax
→ load profile
→ confirm profile is enforced
→ validate allowed file remains readable
→ reproduce restricted file denial
→ capture application exit code
→ capture kernel AppArmor DENIED event
→ identify missing read permission
→ edit profile
→ add minimum required read permission
→ validate corrected profile syntax
→ reload corrected profile
→ validate both files are readable
→ confirm profile remains enforced
→ unload temporary profile
→ remove profile file
→ remove test executable
→ remove test files
→ validate temporary artifacts removed
→ confirm AppArmor remains active
→ confirm kernel AppArmor remains enabled
```

---

## Final Status

```text
AppArmor service baseline              PASS
Kernel AppArmor validation             PASS
apparmor_parser availability           PASS
aa-exec availability                   PASS
aa-status availability                 PASS
Profile directory validation           PASS
Test file creation                     PASS
Test executable creation               PASS
Pre-policy allowed read                PASS
Pre-policy restricted read             PASS
Custom profile creation                PASS
Profile syntax validation              PASS
Profile load validation                PASS
Allowed-path enforcement test          PASS
Restricted-path denial                 PASS
Exit-code validation                   PASS
Kernel DENIED evidence                 PASS
Profile identification                 PASS
Root cause identification              PASS
Policy correction                      PASS
Corrected syntax validation            PASS
Corrected profile reload               PASS
Allowed-path recovery                  PASS
Restricted-path recovery               PASS
Enforcement-preserved validation       PASS
Temporary profile unload               PASS
Profile file cleanup                   PASS
Test executable cleanup                PASS
Test file cleanup                      PASS
Profile removal validation             PASS
Executable removal validation          PASS
File removal validation                PASS
AppArmor final state                   PASS
Kernel AppArmor final state            PASS
```

**INC014 status: RESOLVED / VALIDATED**
