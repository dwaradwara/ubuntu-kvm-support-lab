# Phase 4 — Reproducible Multi-VM Support Environment

## Objective

Convert the manually built support environment into a reproducible Ubuntu/KVM stack managed through OpenTofu, libvirt, and cloud-init while preserving a real application-to-database dependency and monitoring lifecycle.

## Architecture

- `p4-web-01` — `192.168.140.10` — application + node_exporter
- `p4-db-01` — `192.168.140.20` — PostgreSQL + node_exporter
- `p4-monitor-01` — `192.168.140.30` — Prometheus + Alertmanager + node_exporter

The web application queries PostgreSQL over the isolated Phase 4 network and exposes `/health` and the Prometheus metric `phase4_db_up`.

## Failure lifecycle

Healthy state:

`PostgreSQL available → HTTP 200 → phase4_db_up=1`

Controlled failure:

`PostgreSQL stopped → application query fails → HTTP 503 → phase4_db_up=0 → Phase4DatabaseDependencyDown FIRING → Alertmanager active`

Recovery:

`PostgreSQL restored → HTTP 200 → phase4_db_up=1 → Prometheus alert cleared → Alertmanager resolved`

## Reproducibility validation

The existing Phase 4 environment was deliberately destroyed and recreated entirely from the committed infrastructure definitions.

Fresh deployment created 15 OpenTofu-managed resources. Validation confirmed:

- all three VMs running
- cloud-init status `done` on every node
- internal addresses `192.168.140.10`, `.20`, and `.30` reachable
- PostgreSQL accepting connections
- application `/health` returning HTTP 200
- application metric `phase4_db_up 1`
- all three node_exporter targets reporting `UP=1`
- application Prometheus target reporting `UP=1`
- Prometheus rule configuration valid
- Alertmanager operational
- generated PostgreSQL application credential managed by OpenTofu
- final `tofu plan` returning `No changes`

## Observed evidence

The following excerpts were captured during the clean rebuild and controlled dependency-failure validation.

### Clean rebuild

```text
Apply complete! Resources: 15 added, 0 changed, 0 destroyed.
```

```text
192.168.140.10 -> PASS
192.168.140.20 -> PASS
192.168.140.30 -> PASS
```

### Healthy application state

```text
HTTP/1.0 200 OK
{"service": "phase4-web", "database": "up", "detail": "database reachable"}
```

```text
phase4_db_up 1
```

```text
192.168.140.10:9100  UP=1
192.168.140.20:9100  UP=1
192.168.140.30:9100  UP=1
192.168.140.10:8080  UP=1
```

### Service hardening

```text
User=phase4-app
Group=phase4-app
root:phase4-app 750 /opt/phase4-app/app.py
root:phase4-app 640 /etc/phase4-app.env
root:root 600 /etc/phase4-db.env
root:root 750 /usr/local/sbin/phase4-db-bootstrap.sh
```

### Controlled database dependency failure

```text
alertname: Phase4DatabaseDependencyDown
instance: 192.168.140.10:8080
job: phase4-app
severity: critical
state: active
receiver: phase4-default
```

After PostgreSQL recovery:

```text
HTTP/1.0 200 OK
phase4_db_up 1
```

Alertmanager:

```json
[]
```

### Infrastructure convergence

```text
No changes. Your infrastructure matches the configuration.
```


## Support engineering takeaway

The important result is not simply that the services start. The environment demonstrates dependency-aware health checking, observable failure propagation, controlled incident reproduction, recovery validation, infrastructure convergence, and clean rebuild capability.
