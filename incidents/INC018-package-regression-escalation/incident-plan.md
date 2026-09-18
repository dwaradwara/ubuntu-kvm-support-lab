# INC018 — Package Regression, Rollback, and Support Escalation

Status: **completed — retained as the execution plan**

## Purpose

Demonstrate a support workflow for a customer-visible regression immediately after a software package change.

This incident uses locally built demo Debian packages so the failure is deterministic and safe. It is a simulation of the troubleshooting workflow, not a claim that an Ubuntu archive package regressed.

## Files

- `scripts/inc018_build_demo_packages.sh`
- `scripts/inc018_collect_package_evidence.sh`
- support templates under `support/`

## Phase 1 — build demo packages

```bash
bash scripts/inc018_build_demo_packages.sh
ls -lh .lab-artifacts/inc018/
```

The script creates a healthy `1.0` package and an intentionally failing `1.1` package.

## Phase 2 — healthy baseline

```bash
sudo dpkg -i .lab-artifacts/inc018/support-demo_1.0_all.deb
sudo systemctl daemon-reload
sudo systemctl restart support-demo.service
systemctl status support-demo.service --no-pager
curl -fsS http://127.0.0.1:18080/health
dpkg-query -W -f='\${Package} \${Version}\n' support-demo
```

Expected healthy response:

```text
status=ok version=1.0
```

Capture the actual output.

## Phase 3 — controlled bad upgrade

```bash
sudo dpkg -i .lab-artifacts/inc018/support-demo_1.1_all.deb
sudo systemctl daemon-reload
sudo systemctl restart support-demo.service || true
systemctl status support-demo.service --no-pager
journalctl -u support-demo.service -n 80 --no-pager
curl -v http://127.0.0.1:18080/health
bash scripts/inc018_collect_package_evidence.sh
```

## Phase 4 — correlate failure with package change

Evidence must establish installed version, previous version, package-install timestamp, failure timing, and whether unrelated resource/network failures were ruled out.

Useful commands:

```bash
dpkg-query -W -f='\${Package} \${Version}\n' support-demo
apt-cache policy support-demo
grep -F 'support-demo' /var/log/dpkg.log | tail -n 20
journalctl -u support-demo.service --since '-30 min' --no-pager
```

## Phase 5 — rollback / workaround

```bash
sudo dpkg -i .lab-artifacts/inc018/support-demo_1.0_all.deb
sudo systemctl daemon-reload
sudo systemctl restart support-demo.service
sudo apt-mark hold support-demo
```

Validate service state, health endpoint, installed version, and package hold.

## Phase 6 — support communication

Produce:

1. A customer update that separates confirmed facts, workaround, permanent fix status, and the next update checkpoint.
2. An engineering escalation with exact environment, versions, reproduction, logs, package timeline, rollback result, and business impact.

Do not promise an engineering release date that has not been committed.

## Ubuntu release-process connection

For real supported Ubuntu releases, support engineers must distinguish an upstream fix from an Ubuntu package build, verification in the appropriate process, stable-pocket release, and customer installation.

See `docs/ubuntu-development-support-guide.md`.

## Cleanup

```bash
sudo apt-mark unhold support-demo || true
sudo dpkg -r support-demo || true
rm -rf .lab-artifacts/inc018
```

## Final deliverables

Execution completed on 2026-09-18. See `incident-report.md`, `customer-update.md`, `engineering-escalation.md`, `technical-notice.md`, and the sanitized `evidence/` directory.
