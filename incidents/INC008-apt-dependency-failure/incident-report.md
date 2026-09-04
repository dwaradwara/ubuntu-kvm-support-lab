# INC008 — APT Dependency Failure and Recovery

## Summary

A controlled Debian package dependency failure was reproduced on the Ubuntu guest VM.

A custom package named:

```text
inc008-demo
```

was created with a strict dependency on:

```text
inc008-helper (= 1.0)
```

The helper package did not exist when `inc008-demo` was first installed.

As a result, `dpkg` unpacked the package but could not configure it.

The failure was confirmed with:

```bash
sudo apt-get check
```

and:

```bash
sudo dpkg --audit
```

The package manager reported an unmet dependency and showed that `inc008-demo` was unpacked but not configured.

A matching `inc008-helper` package was then created and installed.

After installing the missing dependency, `inc008-demo` was configured successfully.

Final validation confirmed:

```text
apt-get check  → clean
dpkg --audit   → clean
inc008-demo    → installed/configured
inc008-helper  → installed/configured
```

Both test executables also ran successfully.

The temporary packages were then removed and the package manager returned to a clean state.

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

Package tools used:

```text
apt-get
dpkg
dpkg-deb
```

---

## Baseline Package Validation

Before creating the incident, package health was checked:

```bash
sudo apt-get check
```

Observed:

```text
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
```

No dependency errors were reported.

The dpkg database was also audited:

```bash
sudo dpkg --audit
```

Observed:

```text
No output
```

This confirmed there were no packages left unpacked, unconfigured, or otherwise inconsistent.

The package-building tool was verified:

```bash
which dpkg-deb
```

Observed:

```text
/usr/bin/dpkg-deb
```

---

## Demo Package Creation

A temporary build directory was created:

```bash
rm -rf /tmp/inc008
mkdir -p /tmp/inc008/inc008-demo/DEBIAN
mkdir -p /tmp/inc008/inc008-demo/usr/local/bin
```

The package metadata was created as:

```text
Package: inc008-demo
Version: 1.0
Section: misc
Priority: optional
Architecture: all
Depends: inc008-helper (= 1.0)
Maintainer: KVM Support Lab
Description: INC008 controlled dependency failure demo package
```

A simple executable was created at:

```text
/usr/local/bin/inc008-demo
```

The package was then built:

```bash
dpkg-deb --build \
/tmp/inc008/inc008-demo \
/tmp/inc008/inc008-demo_1.0_all.deb
```

The package metadata was verified:

```bash
dpkg-deb -I /tmp/inc008/inc008-demo_1.0_all.deb
```

Relevant output:

```text
Package: inc008-demo
Version: 1.0
Architecture: all
Depends: inc008-helper (= 1.0)
```---

## Failure Reproduction

The deliberately incomplete package was installed:

```bash
sudo dpkg -i /tmp/inc008/inc008-demo_1.0_all.deb
```

`dpkg` unpacked the package but failed during configuration.

Observed:

```text
dpkg: dependency problems prevent configuration of inc008-demo:
 inc008-demo depends on inc008-helper (= 1.0); however:
  Package inc008-helper is not installed.
```

The package was therefore left in an incomplete state.

Additional output showed:

```text
dependency problems - leaving unconfigured
```

---

## Package Health Investigation

APT dependency validation was run:

```bash
sudo apt-get check
```

Observed:

```text
The following packages have unmet dependencies:
 inc008-demo : Depends: inc008-helper (= 1.0) but it is not installable
```

APT also suggested that broken dependencies needed correction.

The dpkg database was then audited:

```bash
sudo dpkg --audit
```

Observed:

```text
The following packages have been unpacked but not yet configured:
 inc008-demo
```

This confirmed the package database itself was readable and functional, but one package remained in an unconfigured state because its required dependency was missing.

---

## Root Cause

The root cause was:

```text
Required dependency inc008-helper (= 1.0) was not installed
```

Failure chain:

```text
Install inc008-demo
→ package unpacked successfully
→ dependency validation executed
→ inc008-helper missing
→ configuration blocked
→ package left unconfigured
→ apt-get check reported unmet dependency
```

The issue was not caused by:

```text
corrupted dpkg database
repository failure
filesystem failure
package archive corruption
```

The evidence pointed specifically to a missing required dependency.

---

## Helper Package Creation

A matching dependency package was created:

```bash
mkdir -p /tmp/inc008/inc008-helper/DEBIAN
mkdir -p /tmp/inc008/inc008-helper/usr/local/bin
```

Package metadata:

```text
Package: inc008-helper
Version: 1.0
Section: misc
Priority: optional
Architecture: all
Maintainer: KVM Support Lab
Description: INC008 helper dependency package
```

A helper executable was created at:

```text
/usr/local/bin/inc008-helper
```

The helper package was built:

```bash
dpkg-deb --build \
/tmp/inc008/inc008-helper \
/tmp/inc008/inc008-helper_1.0_all.deb
```

The resulting package metadata was verified:

```bash
dpkg-deb -I /tmp/inc008/inc008-helper_1.0_all.deb
```

Relevant output:

```text
Package: inc008-helper
Version: 1.0
Architecture: all
```---

## Dependency Recovery

The missing dependency package was installed:

```bash
sudo dpkg -i /tmp/inc008/inc008-helper_1.0_all.deb
```

Observed:

```text
Selecting previously unselected package inc008-helper.
Unpacking inc008-helper (1.0) ...
Setting up inc008-helper (1.0) ...
```

The previously broken package was then configured:

```bash
sudo dpkg --configure inc008-demo
```

Observed:

```text
Setting up inc008-demo (1.0) ...
```

This completed the interrupted package configuration.

---

## Package State Validation

APT dependency health was checked again:

```bash
sudo apt-get check
```

Observed:

```text
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
```

No unmet dependency errors remained.

The dpkg database was audited:

```bash
sudo dpkg --audit
```

Observed:

```text
No output
```

Both packages were inspected:

```bash
dpkg -l inc008-demo inc008-helper
```

Observed package state:

```text
ii  inc008-demo    1.0  all
ii  inc008-helper  1.0  all
```

The `ii` state confirmed both packages were installed and configured successfully.

---

## Functional Validation

The helper executable was tested:

```bash
inc008-helper
```

Observed:

```text
INC008 helper installed
```

The demo application was then tested:

```bash
inc008-demo
```

Observed:

```text
INC008 demo application running
```

This confirmed that the package recovery was not limited to metadata repair; the installed binaries were also functional.

---

## Cleanup

The temporary lab packages were removed:

```bash
sudo apt-get remove -y inc008-demo inc008-helper
```

Observed:

```text
Removing inc008-demo (1.0) ...
Removing inc008-helper (1.0) ...
```

A warning was shown:

```text
directory '/usr/local' not empty so not removed
```

This was expected because `/usr/local` is a shared directory and contained other content.

Package health was checked again:

```bash
sudo apt-get check
```

No dependency errors were reported.

The dpkg database was audited again:

```bash
sudo dpkg --audit
```

Observed:

```text
No output
```

Temporary build files were removed:

```bash
rm -rf /tmp/inc008
```

Package removal was verified:

```bash
dpkg -l inc008-demo inc008-helper
```

Observed:

```text
dpkg-query: no packages found matching inc008-demo
dpkg-query: no packages found matching inc008-helper
```

---

## Result

The package dependency failure was successfully reproduced, diagnosed, repaired, validated, and cleaned up.

Failure path:

```text
inc008-demo installed
→ required dependency missing
→ package unpacked
→ configuration failed
→ package left unconfigured
→ apt-get check reported unmet dependency
```

Recovery path:

```text
Identify missing dependency
→ create matching dependency package
→ install dependency
→ configure original package
→ run apt-get check
→ run dpkg --audit
→ verify package state
→ test executables
```

---

## Technical Findings

1. `dpkg -i` can unpack a package even when required dependencies are missing.
2. A package may therefore exist on disk while remaining unconfigured.
3. `apt-get check` is useful for identifying unmet package dependencies.
4. `dpkg --audit` identifies packages left in incomplete states.
5. Dependency errors should be diagnosed before blindly running repair commands.
6. A locally built dependency cannot be fetched automatically from Ubuntu repositories unless it exists there.
7. Installing the required dependency allows the original package to be configured.
8. `dpkg -l` provides package-state confirmation; `ii` indicates installed and configured.
9. Package-manager recovery should be validated both structurally and functionally.
10. Test packages should be removed after validation to restore a clean lab environment.

---

## Support Troubleshooting Method

The workflow used was:

```text
Baseline
→ Create controlled dependency failure
→ Reproduce install error
→ Check APT health
→ Audit dpkg state
→ Identify missing dependency
→ Build dependency
→ Install dependency
→ Configure broken package
→ Validate package database
→ Validate application execution
→ Cleanup
→ Revalidate package health
```

This approach isolates the exact dependency problem before remediation and verifies that the package manager returns to a healthy state afterward.

---

## Final Status

```text
Package baseline check             PASS
dpkg audit baseline                PASS
Demo package build                 PASS
Missing dependency reproduction    PASS
Unconfigured package detection     PASS
APT dependency diagnosis           PASS
dpkg audit diagnosis               PASS
Root cause identification          PASS
Helper package build               PASS
Dependency installation            PASS
Original package configuration     PASS
APT recovery validation            PASS
dpkg recovery validation           PASS
Package state validation           PASS
Executable validation              PASS
Package cleanup                    PASS
Final package health check         PASS
```

**INC008 status: RESOLVED / VALIDATED**
