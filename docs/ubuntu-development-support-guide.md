# Ubuntu Development Process — Support Engineer Guide

This is a support-focused guide, not a substitute for Ubuntu developer documentation.

## Why this matters in support

A support engineer needs to distinguish:

1. a bug exists upstream;
2. an upstream fix exists;
3. Ubuntu has packaged the fix;
4. that package has been built and published for a particular Ubuntu series;
5. a stable-release update has passed the required verification and reached the appropriate archive pocket;
6. a customer has actually installed the fixed build.

Those are different states. Conflating them creates bad customer expectations.

## Upstream vs Ubuntu package

An upstream project owns its source release process.

Ubuntu distributes source and binary packages built for Ubuntu releases. A fix merged upstream does not automatically mean every supported Ubuntu release immediately contains that fix.

Support should capture both the upstream/project version or commit when relevant and the Ubuntu package version, series, and archive source.

Useful local commands:

```bash
lsb_release -a
apt-cache policy <package>
dpkg-query -W -f='\${Package} \${Version}\n' <package>
grep -F '<package>' /var/log/dpkg.log
```

## Launchpad and package publication

Launchpad participates in Ubuntu package build, publication, bug, and collaboration workflows.

A source package upload is checked and then built for supported architectures before resulting binaries are published. Therefore "source fix exists" and "installable Ubuntu package exists" are not equivalent statements.

## Development release vs stable release

Ubuntu follows a time-based release cycle. After a stable release is published, updates are deliberately more conservative than changes in the development series.

Stable supported releases use the Stable Release Update (SRU) process for eligible non-security fixes so updates remain predictable and regressions are controlled.

## SRU mental model

A support-safe model is:

`bug identified -> fix prepared -> SRU upload/review -> build in -proposed -> verification/tests -> aging/phasing as applicable -> release to -updates -> customer installs fixed package`

The exact process depends on the package and update type, but support should never collapse these stages into a single "fixed" state.

The `-proposed` pocket is used as a staging area for updates before wider stable release. Current Ubuntu LTS behavior intentionally gives proposed packages a lower default APT priority than regular archive packages unless explicitly selected.

Support should not tell a production customer to broadly enable proposed packages merely to "get the newest fixes."

## Regression handling

If a stable update appears to cause a regression:

1. preserve evidence before rollback where possible;
2. identify the exact package version and archive origin;
3. establish a previous known-good version;
4. determine whether the symptom reproduces;
5. use a safe workaround/rollback when appropriate;
6. escalate with complete evidence;
7. do not invent a permanent-fix ETA.

Ubuntu's SRU process explicitly includes regression handling because stable-release updates must prioritize predictability.

## Bug state matters

An upstream fix being committed is not the same state as an Ubuntu package being released.

For support, useful distinctions include:

- bug identified/triaged
- fix committed upstream
- Ubuntu package prepared
- package present in a proposed/testing stage
- fix released in a supported Ubuntu series
- customer host confirmed on the fixed package

Always verify the specific series and package version relevant to the customer.

## Security fixes and Ubuntu Security Notices

Ubuntu Security Notices (USNs) document security fixes in official Ubuntu packages.

For a security case, verify the affected Ubuntu release, affected package/version, relevant CVE/USN status, and whether the fixed package is actually installed.

Do not rely only on the upstream version string; Ubuntu may backport security fixes while retaining a distribution-specific versioning scheme.

## PPAs

Personal Package Archives can build Ubuntu packages using Launchpad infrastructure and are useful for development/testing workflows.

A PPA package is not automatically equivalent to an officially supported Ubuntu archive package.

Support communication must clearly distinguish test packages from supported released packages.

## Customer expectation language

Good:

> We have confirmed that the behavior is associated with package version X. Version Y restores service as a temporary rollback. The permanent Ubuntu package update is being tracked through the appropriate engineering and release process. We will update the case when a verified package is available; we are not assigning an unconfirmed release date.

Bad:

> The upstream fix is merged, so the Ubuntu fix will be available tomorrow.

## Practical investigation checklist

```bash
cat /etc/os-release
uname -a
dpkg-query -W -f='\${Package} \${Version}\n' <package>
apt-cache policy <package>
grep -F '<package>' /var/log/dpkg.log
systemctl status <service> --no-pager
journalctl -u <service> --since '-1 hour' --no-pager
```

## Official references

- Stable Release Updates: https://documentation.ubuntu.com/project/SRU/stable-release-updates/
- Ubuntu release policy: https://documentation.ubuntu.com/project/release-team/ubuntu-releases/
- Ubuntu contributor / package documentation: https://documentation.ubuntu.com/project/contributors/
- Launchpad documentation: https://documentation.ubuntu.com/launchpad/
- Ubuntu Security Notices: https://ubuntu.com/security/notices

Read the current official documentation before giving release-process guidance in a real support case.
