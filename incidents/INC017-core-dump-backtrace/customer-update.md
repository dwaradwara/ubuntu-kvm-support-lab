# INC017 — Customer Update

> Simulated customer-facing communication for the controlled lab incident.

## Initial impact

We confirmed that the affected service was not remaining available after restart. The service process was terminating with a segmentation fault and systemd was marking the unit failed with a core-dump result.

## Confirmed findings

The failure was isolated to the service process itself.

Evidence collected from systemd, the service journal, and the generated core dump showed that the process terminated with `SIGSEGV` (signal 11).

The crash occurred immediately after the service started with the fault-triggering configuration enabled.

## Investigation

We collected the generated core dump and inspected it with GDB.

The backtrace showed the failure passing through the Python `_ctypes` module and `libffi` into a native `strlen` operation. This matched the configured fault-injection path and ruled out systemd as the source of the crash.

## Workaround / recovery

The fault-triggering configuration was disabled and the service was restarted.

The service is now:

- active and running
- operating with the healthy configuration
- producing normal health output

## Current status

**Recovered**

The service returned to a healthy state at **12:45:51 UTC**.

## Permanent resolution

For this controlled lab scenario, removing the fault-triggering configuration is the permanent resolution.

In a real customer case involving an unexpected native crash, support would preserve the core/backtrace, identify the affected package/build, and escalate the crash evidence to the owning engineering team before assigning any permanent-fix timeline.
