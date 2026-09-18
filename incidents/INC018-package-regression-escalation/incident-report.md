# INC018 — Package Regression, Rollback, and Support Escalation

Status: **completed**

## Summary

A controlled package regression was introduced on Ubuntu host `p4-web-01` by upgrading the local demo package `support-demo` from version `1.0` to intentionally broken version `1.1`.

Version `1.0` was healthy and served HTTP 200 from `/health`. Immediately after the upgrade to `1.1`, the systemd-managed service exited with status `42`, port `18080` stopped listening, and the health endpoint returned connection refused.

The package change was correlated with the failure using `dpkg-query`, `apt-cache policy`, `/var/log/dpkg.log`, systemd status, journal logs, socket inspection, and HTTP health checks.

Service was restored by rolling back to the known-good `1.0` package and applying a temporary APT hold to prevent reinstallation of the broken version.

This is a controlled lab simulation and not an Ubuntu archive regression.

## Environment

- Host: `p4-web-01`
- OS: Ubuntu 22.04.5 LTS
- Kernel: `5.15.0-190-generic`
- Package: `support-demo`
- Known-good version: `1.0`
- Regressed version: `1.1`
- Service: `support-demo.service`
- Health endpoint: `http://127.0.0.1:18080/health`

## Healthy baseline

Version `1.0` was installed at approximately **13:46:54 UTC**.

Before the upgrade:

```text
support-demo 1.0
Active: active (running)
status=ok version=1.0
```

The journal recorded successful health requests, including:

```text
13:47:48 "GET /health HTTP/1.1" 200
```

## Change event

At **13:47:53 UTC**, dpkg history recorded:

```text
upgrade support-demo:all 1.0 1.1
...
status installed support-demo:all 1.1
```

This provides a precise package-change timestamp.

## Failure symptoms

Immediately after the `1.1` package was installed and the service restarted:

```text
Active: failed (Result: exit-code)
Process: ... (code=exited, status=42)
Main PID: ... (code=exited, status=42)
```

The application logged:

```text
support-demo 1.1: controlled regression: invalid startup configuration
```

systemd then recorded:

```text
support-demo.service: Main process exited, code=exited, status=42/n/a
support-demo.service: Failed with result 'exit-code'
```

The endpoint failed:

```text
connect to 127.0.0.1 port 18080 failed: Connection refused
```

No listener was present on port `18080`.

## Package evidence

`dpkg-query`:

```text
support-demo 1.1
```

`apt-cache policy`:

```text
Installed: 1.1
Candidate: 1.1
```

The dpkg history established:

```text
13:46:54 install support-demo 1.0
13:46:55 status installed support-demo 1.0
13:47:53 upgrade support-demo 1.0 -> 1.1
13:47:53 status installed support-demo 1.1
```

## Root cause

The controlled `support-demo 1.1` package replaced the healthy service executable with an intentionally broken version that exits immediately with code `42`.

The timing and evidence correlate the service outage directly with the package upgrade:

```text
healthy 1.0
-> HTTP 200
-> upgrade 1.0 to 1.1
-> service restart
-> process exit 42
-> no listener on 18080
-> connection refused
```

This ruled out an unrelated network, socket, or pre-existing service failure.

## Mitigation

The package was rolled back to the known-good version:

```text
support-demo 1.0
```

A temporary package hold was then applied:

```text
support-demo
```

The hold represents a support workaround while a corrected package would be investigated in a real case.

## Recovery validation

At **13:50:04 UTC**, systemd reported:

```text
Active: active (running)
Main PID: 13044
```

Health validation returned:

```text
status=ok version=1.0
```

The journal subsequently showed successful health requests with HTTP 200.

Package validation confirmed:

```text
support-demo 1.0
```

The temporary hold was confirmed with:

```text
support-demo
```

## Recovery time

Failure observed: **13:47:53 UTC**

Healthy service restored: **13:50:04 UTC**

Elapsed recovery time: approximately **2 minutes 11 seconds**.

## Support workflow demonstrated

1. Establish known-good service and package baseline
2. Capture successful application health
3. Apply one controlled package change
4. Confirm customer-visible outage
5. Correlate service failure with package history
6. Verify installed/candidate version
7. Inspect journal and socket state
8. Roll back to known-good package
9. Apply a temporary package hold
10. Validate service, endpoint, package version, and hold
11. Prepare customer communication
12. Prepare engineering escalation

## Ubuntu release-process relevance

In a real Ubuntu support case, an upstream fix, a proposed package, and a released stable Ubuntu update are different states.

A support engineer should not promise a permanent release date solely because a source-level fix exists. The correct approach is to distinguish the immediate workaround from the package/release process and provide evidence-backed updates.

See `docs/ubuntu-development-support-guide.md`.

## Conclusion

This incident demonstrates package-regression troubleshooting using Ubuntu package-management evidence, systemd state, logs, sockets, HTTP validation, rollback, package hold, customer expectation management, and engineering escalation.

This was a controlled local package simulation and is not presented as an Ubuntu archive defect.
