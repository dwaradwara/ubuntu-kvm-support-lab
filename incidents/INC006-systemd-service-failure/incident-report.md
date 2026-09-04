# INC006 — systemd Service Failure and Recovery

## Summary

A controlled systemd service failure was created on the Ubuntu guest VM using a custom service named `inc006-demo.service`.

The service was configured with an `ExecStart` path pointing to:

```text
/usr/local/bin/inc006-demo
```

The referenced executable did not exist.

When the service was started, systemd reported:

```text
status=203/EXEC
```

The service entered a failed state.

The failure was investigated using:

```bash
systemctl status
journalctl
systemctl cat
ls
```

The missing executable was identified as the root cause.

The executable was then created with the correct permissions, the failed state was cleared, and the service was restarted successfully.

The service was enabled and validated across a reboot.

After cleanup, the system returned to:

```text
0 loaded units listed.
```

for `systemctl --failed`.

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

Service manager:

```text
systemd
```

---

## Baseline Validation

Before creating the incident, failed systemd units were checked:

```bash
systemctl --failed
```

Observed:

```text
0 loaded units listed.
```

This confirmed the guest had no existing failed services before the test.

---

## Controlled Service Creation

A custom systemd unit was created:

```bash
sudo tee /etc/systemd/system/inc006-demo.service >/dev/null <<'EOF'
[Unit]
Description=INC006 Demo Application Service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/inc006-demo
Restart=no

[Install]
WantedBy=multi-user.target
EOF
```

systemd configuration was reloaded:

```bash
sudo systemctl daemon-reload
```

The service was then started:

```bash
sudo systemctl start inc006-demo.service
```

The service did not remain healthy.

---

## Failure Evidence

The service status was inspected:

```bash
systemctl status inc006-demo.service --no-pager -l
```

Observed:

```text
Active: failed
Result: exit-code
status=203/EXEC
```

systemd also reported:

```text
inc006-demo.service: Main process exited, code=exited, status=203/EXEC
inc006-demo.service: Failed with result 'exit-code'
```---

## Journal Investigation

Service logs were reviewed:

```bash
journalctl -u inc006-demo.service -n 20 --no-pager
```

Observed:

```text
inc006-demo.service: Main process exited, code=exited, status=203/EXEC
inc006-demo.service: Failed with result 'exit-code'
```

The failure consistently pointed to an execution problem rather than an application-level runtime error.

---

## ExecStart Validation

The configured executable path was checked:

```bash
ls -l /usr/local/bin/inc006-demo
```

Observed:

```text
ls: cannot access '/usr/local/bin/inc006-demo': No such file or directory
```

The unit definition was then inspected:

```bash
systemctl cat inc006-demo.service
```

Relevant configuration:

```text
[Service]
Type=simple
ExecStart=/usr/local/bin/inc006-demo
Restart=no
```

This confirmed that systemd was attempting to execute a file that did not exist.

---

## Root Cause

The root cause was:

```text
Missing executable referenced by ExecStart
```

Failure chain:

```text
systemd service start
→ ExecStart evaluated
→ /usr/local/bin/inc006-demo not found
→ process could not execute
→ status=203/EXEC
→ service entered failed state
```

---

## Recovery

The missing executable was created:

```bash
sudo tee /usr/local/bin/inc006-demo >/dev/null <<'EOF'
#!/bin/bash
while true; do
  echo "INC006 demo service running"
  sleep 30
done
EOF
```

Executable permissions were applied:

```bash
sudo chmod 755 /usr/local/bin/inc006-demo
```

The file was verified:

```bash
ls -l /usr/local/bin/inc006-demo
```

Observed permissions:

```text
-rwxr-xr-x
```

The failed state was cleared:

```bash
sudo systemctl reset-failed inc006-demo.service
```

The service was started again:

```bash
sudo systemctl start inc006-demo.service
```

Service status was checked:

```bash
systemctl status inc006-demo.service --no-pager -l
```

Observed:

```text
Active: active (running)
```

The service log also showed:

```text
INC006 demo service running
```---

## Boot Persistence Validation

The recovered service was enabled:

```bash
sudo systemctl enable inc006-demo.service
```

Enablement was verified:

```bash
systemctl is-enabled inc006-demo.service
```

Observed:

```text
enabled
```

The guest was then rebooted:

```bash
sudo reboot
```

After reconnecting, the service status was checked again:

```bash
systemctl status inc006-demo.service --no-pager -l
```

Observed:

```text
Loaded: loaded
Active: active (running)
```

This confirmed the recovered service started automatically after reboot.

The system-wide failed unit list was also checked:

```bash
systemctl --failed
```

Observed:

```text
0 loaded units listed.
```

---

## Cleanup

After recovery validation, the demo service was removed so it would not interfere with later lab scenarios.

The service was disabled and stopped:

```bash
sudo systemctl disable --now inc006-demo.service
```

The unit file was removed:

```bash
sudo rm /etc/systemd/system/inc006-demo.service
```

The executable was removed:

```bash
sudo rm /usr/local/bin/inc006-demo
```

systemd was reloaded:

```bash
sudo systemctl daemon-reload
```

Failed unit state was cleared:

```bash
sudo systemctl reset-failed
```

Final validation:

```bash
systemctl --failed
```

Observed:

```text
0 loaded units listed.
```

---

## Result

The incident was successfully resolved and validated.

Failure mechanism:

```text
Broken ExecStart target
→ systemd attempted execution
→ executable missing
→ status=203/EXEC
→ service failed
```

Recovery path:

```text
Inspect status
→ inspect journal
→ verify ExecStart path
→ confirm missing executable
→ create executable
→ fix permissions
→ reset failed state
→ restart service
→ validate active state
→ enable service
→ reboot
→ validate persistence
```

---

## Technical Findings

1. `status=203/EXEC` indicates systemd could not execute the configured command.
2. `systemctl status` provides the immediate failure state and exit status.
3. `journalctl -u <service>` provides service-specific runtime evidence.
4. `systemctl cat <service>` confirms the exact unit configuration systemd is using.
5. `ExecStart` paths must reference an existing executable file.
6. Correct file permissions are required before systemd can execute the target.
7. `systemctl reset-failed` clears the failed state before retrying.
8. A successful restart alone does not prove boot persistence.
9. `systemctl enable` plus reboot validation confirms the service starts automatically.
10. Test services should be removed after validation to keep the lab clean.

---

## Support Troubleshooting Method

The workflow used was:

```text
Baseline
→ Reproduce
→ Inspect status
→ Inspect logs
→ Validate configuration
→ Confirm root cause
→ Apply fix
→ Restart
→ Validate
→ Reboot
→ Validate persistence
→ Cleanup
```

This prevents treating a successful command as proof that the service is actually healthy.

---

## Final Status

```text
Baseline failed-unit check       PASS
Controlled systemd failure       PASS
203/EXEC identification          PASS
Journal investigation            PASS
ExecStart validation             PASS
Missing executable confirmed     PASS
Executable recovery              PASS
Permission validation            PASS
Service restart                  PASS
Active-state validation          PASS
Boot persistence                 PASS
Post-reboot validation           PASS
Cleanup                          PASS
Final failed-unit check          PASS
```

**INC006 status: RESOLVED / VALIDATED**
