# INC017 — Engineering Escalation

> Simulated engineering escalation for the controlled lab incident.

## Case summary

- Impact: systemd-managed service unavailable after restart
- Severity: lab simulation
- First observed: 2026-09-18 12:41:17 UTC
- Reproducible: yes
- Workaround available: yes
- Current state: recovered

## Environment

```text
Host: p4-web-01
Service: canonical-crash-demo.service
Runtime: /usr/bin/python3
Executable: /usr/bin/python3.10
Debugger: GNU gdb 12.1
Core handler: systemd-coredump
Crash PID: 12228
```

## Expected behavior

The service should remain active and emit periodic `health=ok` messages.

## Actual behavior

With `TRIGGER_CRASH=1`, the process terminated immediately with SIGSEGV.

systemd recorded:

```text
Main process exited, code=dumped, status=11/SEGV
Failed with result 'core-dump'
```

## Reproduction

1. Set `TRIGGER_CRASH=1` in `/etc/default/canonical-crash-demo`
2. Restart `canonical-crash-demo.service`
3. Observe process termination
4. Inspect with `systemctl status`, `journalctl`, and `coredumpctl`

Reproduction rate: **1/1**

## Crash evidence

`coredumpctl info`:

```text
Signal: 11 (SEGV)
Command Line: /usr/bin/python3 /opt/canonical-gap-lab/inc017_crash_service.py
Executable: /usr/bin/python3.10
Unit: canonical-crash-demo.service
```

GDB:

```text
Program terminated with signal SIGSEGV, Segmentation fault.
#0 __strlen_sse2
#1 _ctypes...
#2 libffi.so.8
#3 libffi.so.8
#4 _ctypes...
#5 _ctypes...
```

## Isolation performed

- systemd launch path: functioning; service starts before process crash
- resource pressure: no evidence of OOM or resource exhaustion
- networking: not involved in failure path
- service configuration: fault occurs only with `TRIGGER_CRASH=1`
- native stack: aligns with the intentional `ctypes` crash path

## Root cause

Controlled invalid native memory access triggered through Python `ctypes`.

## Mitigation result

Restored:

```text
TRIGGER_CRASH=0
```

and restarted the service.

Recovery validation:

```text
ActiveState=active
SubState=running
Main PID=12277
health=ok
```

## Requested engineering action

No product engineering action is required for this controlled lab incident.

In an equivalent unexpected production crash, the requested engineering action would be:

- review the core/backtrace
- identify the defective code path
- correlate with package/build version
- determine whether an existing bug already tracks the issue
- advise supported workaround
- determine the appropriate fix/release process

## Customer expectation set

Service was restored through the known-good configuration. No unconfirmed engineering delivery date was provided.
