# INC018 — Engineering Escalation

> Simulated engineering escalation for the controlled lab incident.

## Case summary

- Impact: service unavailable after package upgrade
- First observed: 2026-09-18 13:47:53 UTC
- Reproducible: yes
- Known-good version: `1.0`
- Regressed version: `1.1`
- Workaround: rollback to `1.0` plus temporary package hold
- Current state: recovered

## Environment

```text
Host: p4-web-01
Ubuntu: 22.04.5 LTS
Kernel: 5.15.0-190-generic
Package: support-demo
Affected version: 1.1
Known-good version: 1.0
Service: support-demo.service
Health endpoint: 127.0.0.1:18080/health
```

## Expected behavior

The service should remain active and return:

```text
status=ok version=1.0
```

or the equivalent healthy response for the installed release.

## Actual behavior

Immediately after upgrading to `1.1`:

```text
Active: failed (Result: exit-code)
Main PID: ... (code=exited, status=42)
```

Application output:

```text
support-demo 1.1: controlled regression: invalid startup configuration
```

Health request:

```text
Connection refused
```

## Package timeline

```text
13:46:54 install support-demo 1.0
13:46:55 status installed support-demo 1.0
13:47:48 health request HTTP 200
13:47:53 upgrade support-demo 1.0 -> 1.1
13:47:53 status installed support-demo 1.1
13:47:53 service exits status 42
13:47:53 service marked failed
```

## Reproduction

1. Install `support-demo 1.0`
2. Confirm service active and health endpoint returns HTTP 200
3. Upgrade package to `support-demo 1.1`
4. Restart service
5. Observe immediate process exit with code `42`
6. Confirm no listener on port `18080`
7. Confirm health endpoint returns connection refused

Reproduction rate: **1/1**

## Isolation already performed

- package change correlation: confirmed via `/var/log/dpkg.log`
- installed version: confirmed as `1.1`
- service manager: systemd successfully starts the process, which exits
- socket state: no listener remains on `18080`
- network path: local loopback request fails because the service process is not listening
- known-good comparison: `1.0` returns HTTP 200 before and after rollback

## Mitigation result

Rollback to `1.0` restored service.

Validation after rollback:

```text
Active: active (running)
status=ok version=1.0
support-demo 1.0
```

Temporary package hold:

```text
support-demo
```

## Requested engineering action

For an equivalent real package regression:

- confirm whether the affected package build contains a defect
- identify or create the appropriate bug
- determine whether the issue exists upstream, in Ubuntu packaging, or in integration
- review the supplied reproduction and package timeline
- advise whether the rollback/hold is the supported temporary mitigation
- determine the appropriate package correction and stable-release process

## Customer expectation already set

The customer has been told that service is restored using the previous known-good version and that the rollback is a temporary mitigation.

No permanent-fix ETA has been promised.
