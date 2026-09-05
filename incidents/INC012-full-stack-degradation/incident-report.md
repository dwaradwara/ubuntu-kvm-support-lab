# INC012 — Full-Stack Degradation Caused by Database Schema Regression

## Summary

A controlled full-stack degradation was reproduced and recovered on the Ubuntu KVM guest.

The environment was built as a real application chain:

```text
Client
  ↓
Nginx :80
  ↓
INC012 backend :8000
  ↓
PostgreSQL :5432
```

Prometheus and node exporter remained active in parallel for host-level monitoring.

A dedicated PostgreSQL database and application role were created:

```text
Database: inc012_db
Role:     inc012_app
```

A simple `healthcheck` table stored the expected database response:

```text
1 | database healthy
```

A Python backend service was created and exposed on:

```text
127.0.0.1:8000
```

The backend queried PostgreSQL on every `/health` request.

Nginx was configured to proxy:

```text
/inc012/
```

to the backend.

The healthy end-to-end request returned:

```text
HTTP/1.1 200 OK
{"status": "healthy", "database": "database healthy"}
```

The controlled failure was introduced by renaming the database table:

```text
healthcheck
→ healthcheck_inc012_broken
```

No service was stopped.

During the incident:

```text
Nginx          → active
Backend        → active
PostgreSQL     → active
Prometheus     → active
SELECT 1       → successful
```

However, the application query failed because the expected relation no longer existed.

The same user-facing request then returned:

```text
HTTP/1.1 503 Service Unavailable
```

with:

```text
"status": "degraded"
"database": "unavailable"
"relation \"healthcheck\" does not exist"
```

This isolated the incident to an application/database schema dependency rather than a service outage.

The table name was restored and the same endpoint immediately recovered to:

```text
HTTP/1.1 200 OK
{"status": "healthy", "database": "database healthy"}
```

The temporary backend, database, role, and Nginx proxy configuration were removed after validation.

Core services remained healthy after cleanup.

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

Primary IP:

```text
192.168.122.170
```

---

## Existing Infrastructure Baseline

Before building the application stack, existing services were checked:

```bash
systemctl is-active nginx
systemctl is-active postgresql
systemctl is-active prometheus
systemctl is-active prometheus-node-exporter
```

Observed:

```text
nginx                    → active
postgresql               → active
prometheus               → active
prometheus-node-exporter → active
```

Listening ports were inspected:

```bash
sudo ss -ltnp | grep -E ':80|:443|:5432|:8000|:8080|:9090|:9100'
```

Observed:

```text
Nginx        → port 80
PostgreSQL   → 127.0.0.1:5432
Prometheus   → port 9090
Node exporter→ port 9100
```

Nothing was listening on:

```text
8000
8080
```

This confirmed that no application backend existed yet.

---

## Nginx Baseline

The default Nginx page was tested:

```bash
curl -i http://127.0.0.1/
```

The standard Nginx welcome page was returned successfully.

This confirmed that the reverse-proxy layer was healthy before any INC012 changes were introduced.

---

## Python and PostgreSQL Driver Validation

Python availability was checked:

```bash
command -v python3
```

Observed:

```text
/usr/bin/python3
```

The PostgreSQL Python driver was checked:

```bash
python3 -c \
"import psycopg2; print('psycopg2 available')" \
2>/dev/null || echo "psycopg2 not installed"
```

Observed initially:

```text
psycopg2 not installed
```

PostgreSQL itself was validated directly:

```bash
sudo -u postgres psql -Atqc "SELECT 1;"
```

Observed:

```text
1
```

This confirmed that PostgreSQL was healthy and only the Python client driver was missing.

---

## psycopg2 Installation

The PostgreSQL Python driver was installed:

```bash
sudo apt-get install -y python3-psycopg2
```

Validation:

```bash
python3 -c \
"import psycopg2; print('psycopg2 available')"
```

Observed:

```text
psycopg2 available
```

Port 8000 was also checked:

```bash
sudo ss -ltnp | grep 8000 || \
echo "Port 8000 free"
```

Observed:

```text
Port 8000 free
```

This confirmed that the backend could safely bind to port 8000.

---

## INC012 Database Creation

A dedicated application role was created:

```bash
sudo -u postgres psql -c \
"CREATE ROLE inc012_app LOGIN PASSWORD 'Inc012Pass2026';"
```

Observed:

```text
CREATE ROLE
```

A dedicated database was created:

```bash
sudo -u postgres createdb \
-O inc012_app \
inc012_db
```

A simple health table was created:

```bash
sudo -u postgres psql -d inc012_db -c \
"CREATE TABLE healthcheck (
    id integer PRIMARY KEY,
    status text NOT NULL
);"
```

Observed:

```text
CREATE TABLE
```

A baseline row was inserted:

```bash
sudo -u postgres psql -d inc012_db -c \
"INSERT INTO healthcheck
 VALUES (1, 'database healthy');"
```

Observed:

```text
INSERT 0 1
```

Read access was granted to the application role:

```bash
sudo -u postgres psql -d inc012_db -c \
"GRANT SELECT ON healthcheck TO inc012_app;"
```

Observed:

```text
GRANT
```

---

## Application Database Connectivity

The application role was tested directly through TCP:

```bash
PGPASSWORD='Inc012Pass2026' \
psql -h 127.0.0.1 \
-U inc012_app \
-d inc012_db \
-c "SELECT * FROM healthcheck;"
```

Observed:

```text
 id |      status
----+------------------
  1 | database healthy
(1 row)
```

This proved:

```text
Application credentials → valid
Database                → reachable
Table                    → present
SELECT permission        → valid
Database data            → healthy
```

---

## Backend Application Creation

A Python backend was created at:

```text
/usr/local/bin/inc012-backend
```

The application used:

```python
psycopg2
```

to connect to:

```text
host     → 127.0.0.1
port     → 5432
database → inc012_db
user     → inc012_app
```

The backend queried:

```sql
SELECT status
FROM healthcheck
WHERE id = 1;
```

If the query succeeded, it returned:

```json
{
  "status": "healthy",
  "database": "database healthy"
}
```

with:

```text
HTTP 200
```

If the database query failed, it returned:

```json
{
  "status": "degraded",
  "database": "unavailable",
  "error": "<database error>"
}
```

with:

```text
HTTP 503
```

The backend listened on:

```text
127.0.0.1:8000
```

---

## Backend Syntax and Permission Validation

The backend file initially needed `/usr/local/bin` to exist.

The directory was created:

```bash
sudo mkdir -p /usr/local/bin
```

The backend file was then created successfully.

A Python compile check was run:

```bash
sudo python3 -m py_compile \
/usr/local/bin/inc012-backend
```

No output was returned.

This confirmed valid Python syntax.

The file was made executable:

```bash
sudo chmod 755 \
/usr/local/bin/inc012-backend
```

Validation:

```bash
ls -l /usr/local/bin/inc012-backend
```

Observed executable permissions:

```text
-rwxr-xr-x
```

---

## Backend systemd Service

A systemd unit was created:

```text
/etc/systemd/system/inc012-backend.service
```

The service definition used:

```ini
[Unit]
Description=INC012 PostgreSQL-backed application
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=simple
ExecStart=/usr/local/bin/inc012-backend
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
```

Systemd configuration was reloaded:

```bash
sudo systemctl daemon-reload
```

The backend was enabled and started:

```bash
sudo systemctl enable --now \
inc012-backend.service
```

Service validation:

```bash
systemctl status \
inc012-backend.service \
--no-pager -l
```

Observed:

```text
Active: active (running)
```

Port validation:

```bash
sudo ss -ltnp | grep 8000
```

Observed:

```text
127.0.0.1:8000
```

---

## Backend Health Validation

The backend was tested directly:

```bash
curl -i \
http://127.0.0.1:8000/health
```

Observed:

```text
HTTP/1.0 200 OK
Content-Type: application/json
```

Response:

```json
{"status": "healthy", "database": "database healthy"}
```

This proved the backend-to-database path was working before Nginx was added.

---

## Nginx Configuration Backup

The active Nginx site was identified and backed up.

The default site was backed up to:

```text
/etc/nginx/sites-available/default.inc012.bak
```

using:

```bash
sudo cp \
/etc/nginx/sites-available/default \
/etc/nginx/sites-available/default.inc012.bak
```

The existing configuration was inspected before modification.

---

## Nginx Reverse Proxy Configuration

A dedicated proxy path was added:

```nginx
location /inc012/ {
    proxy_pass http://127.0.0.1:8000/;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
}
```

This created the end-to-end path:

```text
Client
→ Nginx :80
→ 127.0.0.1:8000
→ PostgreSQL :5432
```

---

## Nginx Configuration Validation

Nginx syntax was checked before reload:

```bash
sudo nginx -t
```

Observed:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Nginx was then reloaded:

```bash
sudo systemctl reload nginx
```

---

## End-to-End Healthy Baseline

The full application path was tested:

```bash
curl -i \
http://127.0.0.1/inc012/health
```

Observed:

```text
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Content-Type: application/json
```

Response:

```json
{"status": "healthy", "database": "database healthy"}
```

This established the healthy full-stack baseline:

```text
Client
→ Nginx
→ backend
→ PostgreSQL
→ healthcheck table
→ HTTP 200
```---

## Controlled Schema Regression

Before introducing the failure, the application stack services were checked:

```bash
systemctl is-active \
nginx \
inc012-backend \
postgresql \
prometheus
```

All relevant services were active.

The expected application table was also confirmed:

```bash
sudo -u postgres psql \
-d inc012_db \
-c "\dt healthcheck"
```

Observed:

```text
Schema |    Name     | Type  | Owner
-------+-------------+-------+----------
public | healthcheck | table | postgres
```

This confirmed the application dependency existed before the incident.

---

## Failure Injection

The controlled failure was introduced by renaming the table used by the backend:

```bash
sudo -u postgres psql \
-d inc012_db \
-c \
"ALTER TABLE healthcheck
 RENAME TO healthcheck_inc012_broken;"
```

Observed:

```text
ALTER TABLE
```

The PostgreSQL server itself was then checked:

```bash
sudo -u postgres psql -Atqc \
"SELECT 1;"
```

Observed:

```text
1
```

This proved PostgreSQL itself remained healthy.

---

## Service Health During Degradation

The core application services were checked:

```bash
systemctl is-active \
nginx \
inc012-backend \
postgresql
```

Observed:

```text
active
active
active
```

This was important because it showed that the incident was not caused by:

```text
Nginx stopping
Backend process stopping
PostgreSQL stopping
TCP listener loss
```

All three application layers remained operational at the process level.

---

## User-Facing Degradation

The exact same Nginx endpoint used during the healthy baseline was tested:

```bash
curl -i \
http://127.0.0.1/inc012/health
```

Observed:

```text
HTTP/1.1 503 Service Unavailable
Server: nginx/1.24.0 (Ubuntu)
Content-Type: application/json
```

The response body reported:

```json
{
  "status": "degraded",
  "database": "unavailable",
  "error": "relation \"healthcheck\" does not exist"
}
```

The SQL error also referenced the backend query:

```text
SELECT status FROM healthcheck WHERE id = 1;
```

This proved that the request successfully passed through:

```text
Client
→ Nginx
→ backend
```

but failed when the backend attempted to access its expected PostgreSQL relation.

---

## Degradation Evidence

During the incident:

```text
Nginx process                → active
Backend process              → active
PostgreSQL process           → active
PostgreSQL basic query       → successful
Application endpoint         → HTTP 503
Database dependency          → unavailable to application
Expected relation            → missing
```

The important distinction was:

```text
Database server healthy
≠
Application database dependency healthy
```

PostgreSQL could successfully process:

```sql
SELECT 1;
```

while the application-specific query failed because the required relation no longer existed under the expected name.

---

## Root Cause Analysis

The backend application contained the query:

```sql
SELECT status
FROM healthcheck
WHERE id = 1;
```

The controlled schema change renamed:

```text
healthcheck
```

to:

```text
healthcheck_inc012_broken
```

The backend was not changed to use the new relation name.

Therefore, the application continued querying:

```text
healthcheck
```

which no longer existed.

Failure chain:

```text
Client sends /inc012/health
→ Nginx proxies request to backend
→ backend process receives request
→ backend connects successfully to PostgreSQL
→ backend executes SELECT against healthcheck
→ PostgreSQL cannot find relation
→ psycopg2 raises database error
→ backend marks response degraded
→ backend returns HTTP 503
→ Nginx forwards HTTP 503 to client
```

The root cause was therefore:

```text
Database schema regression
```

not:

```text
Nginx outage
Backend outage
PostgreSQL outage
Authentication failure
Network failure
```

---

## Recovery

The table name was restored:

```bash
sudo -u postgres psql \
-d inc012_db \
-c \
"ALTER TABLE healthcheck_inc012_broken
 RENAME TO healthcheck;"
```

The expected relation was then checked:

```bash
sudo -u postgres psql \
-d inc012_db \
-c "\dt healthcheck"
```

Observed:

```text
Schema |    Name     | Type  | Owner
-------+-------------+-------+----------
public | healthcheck | table | postgres
```

This confirmed that the expected application schema had been restored.

---

## Direct Database Recovery Validation

The application role was tested again:

```bash
PGPASSWORD='Inc012Pass2026' \
psql -h 127.0.0.1 \
-U inc012_app \
-d inc012_db \
-c "SELECT * FROM healthcheck;"
```

Observed:

```text
 id |      status
----+------------------
  1 | database healthy
(1 row)
```

This proved that:

```text
Application authentication → working
Database access            → working
Table                       → restored
SELECT permission           → working
Expected data               → available
```

---

## End-to-End Recovery Validation

The exact same Nginx endpoint was tested again:

```bash
curl -i \
http://127.0.0.1/inc012/health
```

Observed:

```text
HTTP/1.1 200 OK
Server: nginx/1.24.0 (Ubuntu)
Content-Type: application/json
```

Response:

```json
{"status": "healthy", "database": "database healthy"}
```

No changes were required to:

```text
Nginx
backend process
PostgreSQL service
networking
application credentials
```

Only the database schema dependency was restored.

This strongly confirmed the root cause.

---

## Post-Recovery Service Validation

The infrastructure services were checked:

```bash
systemctl is-active \
nginx \
inc012-backend \
postgresql \
prometheus
```

Observed:

```text
active
active
active
active
```

This confirmed that all core components remained healthy after recovery.

---

## Incident Comparison

### Before Failure

```text
Nginx             active
Backend           active
PostgreSQL        active
healthcheck table present
Application query succeeds
HTTP response     200
Application state healthy
```

### During Failure

```text
Nginx             active
Backend           active
PostgreSQL        active
healthcheck table renamed
PostgreSQL SELECT 1 succeeds
Application query fails
HTTP response     503
Application state degraded
```

### After Recovery

```text
Nginx             active
Backend           active
PostgreSQL        active
healthcheck table restored
Application query succeeds
HTTP response     200
Application state healthy
```

This showed a complete:

```text
healthy
→ degraded
→ recovered
```

full-stack lifecycle.

---

## Cleanup

After recovery was validated, the temporary INC012 environment was removed.

The original Nginx configuration was restored:

```bash
sudo cp \
/etc/nginx/sites-available/default.inc012.bak \
/etc/nginx/sites-available/default
```

Nginx syntax was validated:

```bash
sudo nginx -t
```

Observed:

```text
nginx: the configuration file /etc/nginx/nginx.conf syntax is ok
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

Nginx was reloaded:

```bash
sudo systemctl reload nginx
```

The temporary Nginx backup was removed:

```bash
sudo rm \
/etc/nginx/sites-available/default.inc012.bak
```

---

## Backend Cleanup

The temporary backend service was disabled and stopped:

```bash
sudo systemctl disable --now \
inc012-backend.service
```

The systemd unit was removed:

```bash
sudo rm \
/etc/systemd/system/inc012-backend.service
```

The backend executable was removed:

```bash
sudo rm \
/usr/local/bin/inc012-backend
```

Systemd state was refreshed:

```bash
sudo systemctl daemon-reload
```

---

## Database Cleanup

The temporary database was removed:

```bash
sudo -u postgres dropdb inc012_db
```

The temporary role was removed:

```bash
sudo -u postgres psql -c \
"DROP ROLE inc012_app;"
```

Observed:

```text
DROP ROLE
```

---

## Final Core Service Validation

The remaining infrastructure services were checked:

```bash
systemctl is-active \
nginx \
postgresql \
prometheus \
prometheus-node-exporter
```

Observed:

```text
active
active
active
active
```

This confirmed that the controlled INC012 environment was removed without damaging the base lab services.

---

## Backend Cleanup Validation

The temporary backend service was checked:

```bash
systemctl status \
inc012-backend.service \
--no-pager -l
```

Observed:

```text
Unit inc012-backend.service could not be found.
```

This confirmed that the temporary systemd unit had been removed successfully.

---

## Database Cleanup Validation

The temporary database was checked:

```bash
sudo -u postgres psql -Atqc \
"SELECT datname
 FROM pg_database
 WHERE datname='inc012_db';"
```

Observed:

```text
No output
```

The temporary role was checked:

```bash
sudo -u postgres psql -Atqc \
"SELECT rolname
 FROM pg_roles
 WHERE rolname='inc012_app';"
```

Observed:

```text
No output
```

This confirmed that both INC012 database objects had been removed.

---

## Final Architecture State

The temporary INC012 application stack was removed.

The persistent lab infrastructure remained:

```text
Nginx                    → active
PostgreSQL               → active
Prometheus               → active
Prometheus node exporter → active
```

Temporary components removed:

```text
INC012 backend service   → removed
INC012 backend binary    → removed
INC012 Nginx proxy block → removed
INC012 database          → removed
INC012 role              → removed
```

---

## Technical Findings

1. A full-stack application can return an error even when every major service process is running.
2. Process health and application health are not the same thing.
3. PostgreSQL successfully answering `SELECT 1` does not prove that an application's required schema is intact.
4. Application-specific database queries should be tested during database incident investigation.
5. Schema regressions can produce user-facing failures without causing a database outage.
6. Returning HTTP `503 Service Unavailable` from a degraded backend provides a clear operational signal.
7. Nginx successfully returning a backend-generated 503 proves that the reverse-proxy path can still be functioning during an application failure.
8. Comparing the exact same endpoint before, during, and after an incident provides strong evidence of causality.
9. A direct database query using the application credentials helps separate authentication problems from schema problems.
10. Infrastructure troubleshooting should identify the failing layer instead of restarting healthy services blindly.
11. Configuration backups should be created before modifying Nginx.
12. `nginx -t` should be run before every configuration reload.
13. Temporary incident infrastructure should be removed after validation.
14. Cleanup should preserve unrelated healthy services.
15. End-to-end validation is stronger than checking individual processes alone.

---

## Support Troubleshooting Method

The workflow used was:

```text
Inspect existing infrastructure
→ validate Nginx
→ validate PostgreSQL
→ validate Prometheus
→ identify missing application layer
→ install PostgreSQL Python driver
→ create dedicated application database
→ create application role
→ create healthcheck table
→ validate application database access
→ create Python backend
→ validate Python syntax
→ create systemd service
→ validate backend port and health
→ back up Nginx configuration
→ configure Nginx reverse proxy
→ validate Nginx syntax
→ establish end-to-end HTTP 200 baseline
→ verify all services healthy
→ introduce controlled schema regression
→ verify PostgreSQL remains healthy
→ verify services remain active
→ reproduce HTTP 503
→ inspect application database error
→ identify missing relation as root cause
→ restore schema
→ validate direct database access
→ retest exact user-facing endpoint
→ confirm HTTP 200 recovery
→ restore Nginx configuration
→ remove temporary backend
→ remove temporary database and role
→ validate core services
→ validate temporary resources removed
```

---

## Final Status

```text
Existing Nginx validation             PASS
Existing PostgreSQL validation        PASS
Existing Prometheus validation        PASS
Python availability                   PASS
psycopg2 dependency installation      PASS
Port 8000 availability                PASS
Application role creation             PASS
Application database creation         PASS
Healthcheck table creation            PASS
Application DB access validation      PASS
Backend creation                      PASS
Backend syntax validation             PASS
Backend executable permissions        PASS
systemd backend creation              PASS
Backend startup                       PASS
Port 8000 validation                  PASS
Direct backend health check           PASS
Nginx configuration backup            PASS
Reverse proxy configuration           PASS
Nginx syntax validation               PASS
End-to-end healthy baseline           PASS
Schema regression reproduction        PASS
PostgreSQL health during failure      PASS
Service health during failure         PASS
HTTP 503 degradation validation       PASS
Database error identification         PASS
Root cause identification             PASS
Schema restoration                    PASS
Application DB recovery validation    PASS
HTTP 200 recovery validation          PASS
Post-recovery service validation      PASS
Nginx restoration                     PASS
Temporary backend cleanup             PASS
Temporary database cleanup            PASS
Temporary role cleanup                PASS
Core service final validation         PASS
Backend removal validation            PASS
Database removal validation           PASS
Role removal validation               PASS
```

**INC012 status: RESOLVED / VALIDATED**

---

# Phase 2 — Multi-VM Database Storage Exhaustion

## Upgrade Objective

The original full-stack incident was extended into a multi-VM storage exhaustion scenario spanning the web, database, and monitoring tiers.

Environment:

- `vm-web-01` — `192.168.100.10`
  - Nginx
  - PHP-FPM
  - database-backed health endpoint
- `vm-db-01` — `192.168.100.20`
  - PostgreSQL 14
  - database: `enterprise_app`
  - dedicated incident disk: `/dev/vdb`
  - tablespace mount: `/mnt/inc012-db`
- `vm-monitor-01` — `192.168.100.30`
  - Prometheus
  - Alertmanager
- private network: `192.168.100.0/24`

Failure path:

```text
Client
  |
  v
vm-web-01
Nginx + PHP-FPM
  |
  | TCP/5432
  v
vm-db-01
PostgreSQL
  |
  | /dev/vdb + node_exporter :9100
  v
vm-monitor-01
Prometheus + Alertmanager
```

## Healthy Baseline

The dedicated PostgreSQL tablespace filesystem initially reported:

```text
usage_percent = 8.03
```

The application returned:

```text
HTTP 200
```

and PostgreSQL writes succeeded through the web tier.

The disk alert was healthy and inactive:

```text
DBDiskNearlyFull state=inactive health=ok
```

## Stage 1 — Capacity Warning

Controlled data was written to the isolated database disk until Prometheus reported:

```text
usage_percent = 88.49
```

The alert transitioned to:

```text
DBDiskNearlyFull firing 192.168.100.20:9100 critical
```

At this point the application still returned:

```text
HTTP 200
```

This demonstrated that monitoring detected the capacity problem before customer-facing failure.

## Stage 2 — Storage Exhaustion

The isolated filesystem was then filled to:

```text
/dev/vdb  224M  219M  0  100%  /mnt/inc012-db
```

The DB VM root filesystem remained healthy at approximately 19% usage, and PostgreSQL itself remained active.

A PostgreSQL write requiring additional blocks failed with:

```text
ERROR: could not extend file
No space left on device
HINT: Check free disk space.
```

The PostgreSQL server log recorded the same `ENOSPC` root cause.

## Full-Stack Degradation

With the database tablespace exhausted, the web application returned:

```text
HTTP 503
{"status":"degraded","database":"write_failed"}
```

At the same time:

```text
Nginx       active
PHP-FPM     active
PostgreSQL  active
```

This proved that healthy processes do not guarantee a healthy application.

Alertmanager showed the storage alert as active and critical.

## Recovery

The temporary filler data was removed from the dedicated incident filesystem.

No PostgreSQL restart was required.

Prometheus then reported:

```text
usage_percent = 8.27
```

The alert returned to:

```text
DBDiskNearlyFull state=inactive health=ok
```

Alertmanager confirmed there were no active `DBDiskNearlyFull` alerts.

The application recovered to:

```text
HTTP 200
```

## Phase 2 Incident Lifecycle

```text
8.03% healthy baseline
→ controlled storage consumption
→ 88.49%
→ DBDiskNearlyFull FIRING
→ application still HTTP 200
→ filesystem reaches 100%
→ PostgreSQL write fails with ENOSPC
→ application HTTP 503
→ filler data removed
→ 8.27%
→ application HTTP 200
→ Prometheus INACTIVE
→ Alertmanager CLEARED
```

## Phase 2 Result

This upgrade demonstrates end-to-end troubleshooting across application, Linux service, PostgreSQL, storage, virtualization, Prometheus, and Alertmanager layers.

The key diagnostic lesson is that service status alone is insufficient. PostgreSQL continued accepting connections while writes failed because its dedicated tablespace filesystem had no free blocks. The customer-facing symptom appeared at the web tier, but the root cause was storage exhaustion on the database tier.

---

## Phase 3 Support Review

### Before / Failure / After Comparison

| Check | Healthy Baseline | Failure | Recovery |
| --- | --- | --- | --- |
| DB filesystem usage | 8.03% | 100% | 8.27% |
| Prometheus storage alert | inactive | FIRING | inactive |
| Alertmanager | no active alert | ACTIVE critical alert | CLEARED |
| PostgreSQL service | active | active | active |
| PostgreSQL writes | successful | ENOSPC / write failure | successful |
| Web application | HTTP 200 | HTTP 503 | HTTP 200 |
| Root filesystem | healthy | healthy | healthy |
| Dedicated tablespace | healthy | exhausted | recovered |

### Customer-Facing Symptom

A customer could report:

```text
The application is online but database-backed operations are failing.
The web endpoint returns HTTP 503 even though the web server and
database services still appear to be running.
```

The investigation separates service availability from application health:

```text
HTTP 503
→ verify Nginx/PHP-FPM
→ verify database reachability
→ verify PostgreSQL service
→ test database write
→ inspect PostgreSQL error
→ identify ENOSPC
→ inspect database tablespace filesystem
→ correlate Prometheus/Alertmanager evidence
```

### Example Support Ticket Update

```text
Status: Resolved

The application degraded from HTTP 200 to HTTP 503 because the
dedicated PostgreSQL tablespace filesystem reached 100% capacity.

Nginx, PHP-FPM, and PostgreSQL remained active, but PostgreSQL writes
failed with 'No space left on device'. Monitoring had detected the
capacity condition earlier at 88.49% usage and raised the
DBDiskNearlyFull alert.

Temporary filler data was removed from the isolated database disk.
No PostgreSQL restart was required.

Final validation confirmed:
- filesystem usage returned to 8.27%
- PostgreSQL writes succeeded
- application returned HTTP 200
- Prometheus alert became inactive
- Alertmanager alert cleared
```

### What I Would Do Differently

1. Capture timestamps at every monitoring, failure, remediation, and validation milestone.
2. Record filesystem block and inode usage before generating load.
3. Capture the exact Prometheus query result at every alert transition.
4. Preserve the PostgreSQL log excerpt containing the first ENOSPC event.
5. Define warning and critical capacity thresholds before the test.
6. Add automated cleanup safeguards so filler data cannot affect the VM root filesystem.
7. Validate both reads and writes because database connectivity alone does not prove database health.

### Prevention and Operational Controls

Monitor both block capacity and inode capacity:

```bash
df -hT /mnt/inc012-db
df -i /mnt/inc012-db
```

Identify large consumers before the filesystem reaches a critical state:

```bash
sudo du -xhd1 /mnt/inc012-db | sort -h
```

Verify PostgreSQL service and connectivity separately from write capability:

```bash
systemctl is-active postgresql
pg_isready
```

A database-backed application health check should also perform a
controlled query or write-capability test where appropriate.

Prometheus should alert before exhaustion using filesystem metrics such as:

```text
node_filesystem_avail_bytes
node_filesystem_size_bytes
```

Operational thresholds should leave enough time for investigation and
capacity remediation before PostgreSQL reaches ENOSPC.

### Timestamp Note

Exact per-command timestamps were not preserved consistently during the
original INC012 execution. They are therefore not reconstructed.

Future captures should record milestones with:

```bash
date -Is
```

and preserve timestamped service/database evidence with:

```bash
journalctl -u postgresql --no-pager -o short-iso
```

### Relevant Documentation

- [Ubuntu Server: About Logical Volume Management](https://documentation.ubuntu.com/server/explanation/storage/about-lvm/index.html)
- [PostgreSQL 14: Tablespaces](https://www.postgresql.org/docs/14/manage-ag-tablespaces.html)
- [Prometheus: Alerting overview](https://prometheus.io/docs/alerting/latest/overview/)
- [Prometheus: Alerting rules](https://prometheus.io/docs/prometheus/latest/configuration/alerting_rules/)
- [Prometheus: Monitoring Linux host metrics with Node Exporter](https://prometheus.io/docs/guides/node-exporter/)
- [Prometheus Alertmanager: Configuration](https://prometheus.io/docs/alerting/latest/configuration/)
