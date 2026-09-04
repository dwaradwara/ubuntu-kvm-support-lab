# ubuntu-kvm-support-lab

Self-directed Ubuntu/KVM production-support lab built around controlled failure, diagnosis, recovery, and verification scenarios relevant to Canonical Linux support engineering.

## Purpose

This repository documents hands-on troubleshooting across Ubuntu, KVM/QEMU, libvirt, systemd, networking, storage, package management, cloud-init, PostgreSQL, Prometheus, Snap, AppArmor, cgroups, and Linux network buffers.

Each incident follows the same support workflow:

**Symptom → Detection → Investigation → Root Cause → Fix → Verification → Prevention**

The goal is not only to make a service work again, but to collect evidence, isolate the failing layer, validate the recovery, and leave the environment clean.

## Environment

- Virtualization: KVM/QEMU with libvirt
- Lab host: Ubuntu userspace under WSL2
- Guest: Ubuntu Server 24.04.4 LTS
- Primary VM: `ubuntu-guest-01`
- Guest hostname: `lab-guest-01`
- Primary libvirt network: NAT via `virbr0`
- Additional networking: isolated libvirt network
- Storage: qcow2 disk images, snapshots, and resize/recovery workflows
- Core guest services used across incidents: Nginx, PostgreSQL, Prometheus, node exporter

## Incidents — 16 Documented

| ID | Incident | Category | Status |
|---|---|---|---|
| [INC001](incidents/INC001-nginx-service-failure/incident-report.md) | Nginx Service Failure | Service / systemd | Resolved |
| [INC002](incidents/INC002-guest-network-loss/incident-report.md) | KVM Guest Network Loss | KVM Networking | Resolved |
| [INC003](incidents/INC003-isolated-network/incident-report.md) | Isolated libvirt Network Failure | KVM Networking | Resolved |
| [INC004](incidents/INC004-storage-snapshot-recovery/incident-report.md) | VM Storage Snapshot Recovery | Storage / qcow2 | Resolved |
| [INC005](incidents/INC005-disk-full-recovery/incident-report.md) | Guest Disk-Full Recovery | Storage | Resolved |
| [INC006](incidents/INC006-systemd-service-failure/incident-report.md) | systemd Service Misconfiguration | systemd | Resolved |
| [INC007](incidents/INC007-netplan-configuration-failure/incident-report.md) | Netplan Configuration Failure | Ubuntu Networking | Resolved |
| [INC008](incidents/INC008-apt-dependency-failure/incident-report.md) | APT/dpkg Dependency Failure | Package Management | Resolved |
| [INC009](incidents/INC009-cloud-init-datasource-recovery/incident-report.md) | cloud-init Datasource Recovery | Provisioning | Resolved |
| [INC010](incidents/INC010-postgresql-connection-policy-failure/incident-report.md) | Cross-VM PostgreSQL Connection Policy Failure | Database / Networking / Access | Resolved |
| [INC011](incidents/INC011-prometheus-alert-lifecycle/incident-report.md) | Prometheus + Alertmanager Resource Alert Lifecycle | Monitoring / Observability | Resolved |
| [INC012](incidents/INC012-full-stack-degradation/incident-report.md) | Multi-VM Database Storage Exhaustion | Application / Database / Storage / Monitoring | Resolved |
| [INC013](incidents/INC013-snap-confinement-failure/incident-report.md) | Snap Strict-Confinement Failure | Snap / Security | Resolved |
| [INC014](incidents/INC014-apparmor-policy-block/incident-report.md) | AppArmor Policy Block | Security | Resolved |
| [INC015](incidents/INC015-cgroup-oom-kill/incident-report.md) | Controlled cgroup OOM Kill | Kernel / Memory | Resolved |
| [INC016](incidents/INC016-udp-receive-buffer-overflow/incident-report.md) | UDP Receive-Buffer Overflow | Kernel / Networking | Resolved |

## Support Automation

The roadmap also requires scripting evidence in Bash, Python, and Perl.

| Script | Language | Purpose |
|---|---|---|
| [`kvm_diagnostic.sh`](scripts/kvm_diagnostic.sh) | Bash | Collect KVM/libvirt host diagnostic information |
| [`ubuntu_health.sh`](scripts/ubuntu_health.sh) | Bash | Produce a quick Ubuntu system-health assessment |
| [`vm_snapshot.sh`](scripts/vm_snapshot.sh) | Bash | Manage VM snapshot create/list/restore/delete lifecycle |
| [`kvm_monitor.py`](scripts/kvm_monitor.py) | Python | Generate KVM VM state reports and flag stopped guests |
| [`log_parser.pl`](scripts/log_parser.pl) | Perl | Parse Linux logs for errors, failed services, OOM events, and disk-full patterns |

## Skills Demonstrated

- KVM/QEMU deployment and troubleshooting
- libvirt VM, network, and storage management
- qcow2 snapshot and disk-recovery workflows
- Ubuntu systemd diagnostics with `systemctl` and `journalctl`
- Netplan configuration and network recovery
- APT/dpkg dependency diagnosis
- cloud-init datasource diagnosis and NoCloud recovery
- PostgreSQL connectivity and `pg_hba.conf` troubleshooting
- Prometheus, node exporter, and Alertmanager alert lifecycle validation
- Snap strict confinement and devmode comparison
- AppArmor denial diagnosis and policy recovery
- cgroup v2 memory limits and OOM-kill investigation
- UDP socket receive-buffer drop analysis using `/proc/net/snmp`
- Bash, Python, and Perl support automation
- Before/after validation and cleanup discipline

## Multi-VM Enterprise Support Architecture

The advanced incidents use separate application, database, and monitoring VMs on an isolated libvirt network.

\`\`\`text
Client
  |
  v
vm-web-01 — 192.168.100.10
Nginx + PHP-FPM
  |
  | PostgreSQL / TCP 5432
  v
vm-db-01 — 192.168.100.20
PostgreSQL 14
  |
  | node_exporter :9100
  v
vm-monitor-01 — 192.168.100.30
Prometheus + Alertmanager
\`\`\`

This architecture supports cross-VM troubleshooting across HTTP, Linux services, networking, PostgreSQL access control, storage, resource pressure, metrics, and alerting.

## Strongest Incident Examples

### INC009 — cloud-init Datasource Recovery
A multi-stage failure that progressed from an installer disable marker to datasource detection failure. Recovery required a local NoCloud seed, fresh cloud-init initialization, libvirt network recovery, SSH host-key handling, and offline qcow2 account recovery.

### INC012 — Multi-VM Database Storage Exhaustion
Demonstrates a complete infrastructure-to-application failure chain. A dedicated PostgreSQL tablespace filesystem progressed from 8.03% usage to an 88.49% Prometheus warning and finally 100% exhaustion. PostgreSQL remained active but returned \`No space left on device\`, the web application degraded from HTTP 200 to HTTP 503, Alertmanager received the critical storage alert, and recovery restored HTTP 200 with the alert cleared.

### INC013 / INC014 — Snap and AppArmor
Uses kernel audit evidence to distinguish application failure from Linux security-policy enforcement and validates recovery with controlled A/B testing.

### INC015 — cgroup OOM
Uses a bounded systemd cgroup rather than host-wide memory exhaustion to reproduce an OOM kill safely and correlate systemd, journal, and kernel evidence.

### INC016 — UDP Receive-Buffer Overflow
Correlates sent/received packet counts with the kernel `RcvbufErrors` counter, then validates recovery with zero new receive-buffer errors.

## Repository Structure

```text
ubuntu-kvm-support-lab/
├── README.md
├── incidents/
│   ├── INC001-nginx-service-failure/
│   ├── INC002-guest-network-loss/
│   ├── INC003-isolated-network/
│   ├── INC004-storage-snapshot-recovery/
│   ├── INC005-disk-full-recovery/
│   ├── INC006-systemd-service-failure/
│   ├── INC007-netplan-configuration-failure/
│   ├── INC008-apt-dependency-failure/
│   ├── INC009-cloud-init-datasource-recovery/
│   ├── INC010-postgresql-connection-policy-failure/
│   ├── INC011-prometheus-alert-lifecycle/
│   ├── INC012-full-stack-degradation/
│   ├── INC013-snap-confinement-failure/
│   ├── INC014-apparmor-policy-block/
│   ├── INC015-cgroup-oom-kill/
│   └── INC016-udp-receive-buffer-overflow/
└── scripts/
    ├── kvm_diagnostic.sh
    ├── ubuntu_health.sh
    ├── vm_snapshot.sh
    ├── kvm_monitor.py
    └── log_parser.pl
```

## Incident Documentation Standard

Incident reports are intended to preserve:

1. Symptom and impact
2. Detection method
3. Investigation commands and observed evidence
4. Root cause
5. Recovery/fix
6. Verification with before/after comparison
7. Prevention or operational lessons

All incidents are controlled lab failures. Temporary test resources are removed after validation unless a component is intentionally retained as part of the base lab environment.
