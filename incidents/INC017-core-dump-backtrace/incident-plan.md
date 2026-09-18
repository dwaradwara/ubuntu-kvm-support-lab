# INC017 — systemd Service Crash and Core-Dump Backtrace

Status: **planned / not yet executed**

## Purpose

Demonstrate explicit Ubuntu crash troubleshooting with a reproducible service failure and native core-dump investigation.

## Scenario

A systemd-managed Python service is healthy under normal configuration. A controlled environment flag activates a deliberate segmentation fault through Python's `ctypes` interface.

The support objective is not merely to restart the service. The objective is to prove the crash path using service logs, coredump metadata, and a debugger backtrace.

## Required host

Use an isolated Ubuntu VM from the lab.

Recommended packages:

```bash
sudo apt update
sudo apt install -y gdb systemd-coredump
```

Confirm:

```bash
systemctl status systemd-coredump.socket --no-pager || true
coredumpctl --version
gdb --version
```

## Files

- `scripts/inc017_crash_service.py`
- `scripts/inc017_setup.sh`
- `scripts/inc017_validate.sh`

## Phase 1 — healthy baseline

Install the demo service:

```bash
sudo ./scripts/inc017_setup.sh
```

Validate:

```bash
./scripts/inc017_validate.sh
systemctl status canonical-crash-demo.service --no-pager
journalctl -u canonical-crash-demo.service -n 30 --no-pager
```

Capture service state, MainPID, recent journal, and process command line.

## Phase 2 — controlled failure

```bash
sudo sed -i 's/^TRIGGER_CRASH=.*/TRIGGER_CRASH=1/' /etc/default/canonical-crash-demo
sudo systemctl restart canonical-crash-demo.service
```

Expected symptom: the service terminates abnormally and systemd records a failure.

Collect:

```bash
systemctl status canonical-crash-demo.service --no-pager
journalctl -u canonical-crash-demo.service -n 80 --no-pager
coredumpctl list --no-pager | tail -n 20
```

## Phase 3 — core and backtrace

```bash
coredumpctl info python3 --no-pager
sudo coredumpctl gdb python3
```

Inside gdb capture at minimum:

```text
bt
thread apply all bt
info sharedlibrary
quit
```

The exact frames depend on Ubuntu/Python versions. Do not hard-code an expected stack trace into the final evidence.

## Phase 4 — remediation

```bash
sudo sed -i 's/^TRIGGER_CRASH=.*/TRIGGER_CRASH=0/' /etc/default/canonical-crash-demo
sudo systemctl restart canonical-crash-demo.service
./scripts/inc017_validate.sh
```

## Root-cause standard

The final report must connect all three layers:

1. systemd records abnormal process termination.
2. coredumpctl identifies a core for the service process.
3. gdb backtrace places the crash in the deliberately invoked ctypes/native crash path.

## Cleanup

```bash
sudo systemctl disable --now canonical-crash-demo.service || true
sudo rm -f /etc/systemd/system/canonical-crash-demo.service
sudo rm -f /etc/default/canonical-crash-demo
sudo rm -rf /opt/canonical-gap-lab
sudo systemctl daemon-reload
```

## Final deliverables after execution

Create `incident-report.md`, `customer-update.md`, `engineering-escalation.md`, and sanitized evidence files.

Do not mark the incident complete until those artifacts are backed by actual execution.
