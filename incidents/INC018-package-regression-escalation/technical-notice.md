# Technical Notice — support-demo 1.1 Startup Regression

> Controlled lab notice. This package is a local demo package and not an Ubuntu archive package.

## Summary

The controlled `support-demo 1.1` package causes `support-demo.service` to exit immediately during startup.

The known-good `1.0` package remains functional.

## Affected environment

- Ubuntu 22.04.5 LTS
- Package: `support-demo`
- Affected version: `1.1`
- Known-good version: `1.0`
- Service: `support-demo.service`

## Symptoms

```text
Active: failed (Result: exit-code)
status=42
```

The service journal contains:

```text
support-demo 1.1: controlled regression: invalid startup configuration
```

Requests to:

```text
http://127.0.0.1:18080/health
```

return connection refused because no listener remains on port `18080`.

## Confirmation

Check package version:

```bash
dpkg-query -W -f='${Package} ${Version}\n' support-demo
```

Check package history:

```bash
grep -F 'support-demo' /var/log/dpkg.log
```

Check service:

```bash
systemctl status support-demo.service --no-pager
journalctl -u support-demo.service -n 80 --no-pager
```

Check listener:

```bash
ss -ltnp | grep ':18080'
```

## Workaround

Roll back to the known-good `1.0` package and restart the service.

After recovery, a temporary package hold may be used to prevent accidental reinstallation of the affected version while the underlying issue is investigated.

## Validation

```bash
systemctl status support-demo.service --no-pager
curl -fsS http://127.0.0.1:18080/health
dpkg-query -W -f='${Package} ${Version}\n' support-demo
apt-mark showhold | grep -Fx support-demo
```

Expected healthy results include:

```text
active (running)
status=ok version=1.0
support-demo 1.0
support-demo
```

## Permanent resolution

For this controlled lab, version `1.1` is intentionally broken.

In a real Ubuntu support case, the permanent resolution would depend on the owning engineering/package workflow. An upstream fix alone should not be presented as equivalent to a released Ubuntu stable package.

## Scope

This notice documents a controlled local package simulation only.
