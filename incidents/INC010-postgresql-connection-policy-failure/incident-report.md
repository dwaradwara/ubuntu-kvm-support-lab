# INC010 — PostgreSQL Connection Policy Failure and Recovery

## Summary

A controlled PostgreSQL application connection failure was reproduced and recovered on the Ubuntu KVM guest.

PostgreSQL was not initially installed on the VM, so PostgreSQL 16 was installed and validated before creating the incident.

A dedicated application role and database were created:

```text
Role:     inc010_app
Database: inc010_db
```

Baseline TCP connectivity through localhost was verified successfully:

```text
inc010_app | inc010_db
```

The active PostgreSQL authentication configuration was identified as:

```text
/etc/postgresql/16/main/pg_hba.conf
```

A targeted `pg_hba.conf` rule was then added:

```text
host    inc010_db    inc010_app    127.0.0.1/32    reject
```

This rule rejected only the INC010 application connection while leaving the PostgreSQL server itself online.

After reloading PostgreSQL, the same application connection failed with:

```text
FATAL: pg_hba.conf rejects connection for host "127.0.0.1",
user "inc010_app",
database "inc010_db"
```

During the failure:

```text
PostgreSQL cluster → online
Port 5432          → listening
Database service   → healthy
Application access → rejected
```

PostgreSQL logs independently confirmed that the connection was being rejected by `pg_hba.conf`.

The original authentication configuration was then restored and PostgreSQL was reloaded.

The exact same application connection succeeded again.

The temporary database, role, and configuration backup were removed after validation.

PostgreSQL remained installed and healthy after cleanup.

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

## Initial PostgreSQL Baseline

PostgreSQL availability was checked before starting the incident:

```bash
command -v psql || echo "psql not installed"
```

Observed:

```text
psql not installed
```

The PostgreSQL systemd service was checked:

```bash
systemctl status postgresql --no-pager -l
```

Observed:

```text
Unit postgresql.service could not be found.
```

Port 5432 was checked:

```bash
sudo ss -ltnp | grep 5432 || \
echo "Nothing listening on port 5432"
```

Observed:

```text
Nothing listening on port 5432
```

This confirmed that PostgreSQL was not yet installed and no database process was listening on the default PostgreSQL port.

---

## PostgreSQL Package Availability

The PostgreSQL package candidate was inspected:

```bash
apt-cache policy postgresql
```

Observed:

```text
Installed: (none)
Candidate: 16+257build1.1
```

PostgreSQL 16 was available from the configured Ubuntu repositories.

---

## PostgreSQL Installation

PostgreSQL was installed:

```bash
sudo apt-get install -y postgresql
```

After installation, the client version was checked:

```bash
psql --version
```

Observed:

```text
psql (PostgreSQL) 16.15
```

The PostgreSQL cluster was inspected:

```bash
sudo pg_lsclusters
```

Observed:

```text
Ver Cluster Port Status Owner    Data directory              Log file
16  main    5432 online postgres /var/lib/postgresql/16/main /var/log/postgresql/postgresql-16-main.log
```

This confirmed that PostgreSQL 16 was running with the default `main` cluster.

---

## Service and Listener Validation

PostgreSQL service state was checked:

```bash
systemctl status postgresql --no-pager -l
```

Observed:

```text
Active: active (exited)
```

The underlying PostgreSQL cluster remained online.

The TCP listener was checked:

```bash
sudo ss -ltnp | grep 5432
```

Observed:

```text
127.0.0.1:5432
```

with the PostgreSQL process listening on the default port.

Baseline database service health was therefore confirmed before introducing the failure.

---

## Application Test Objects

A dedicated application role was created:

```bash
sudo -u postgres psql -c \
"CREATE ROLE inc010_app LOGIN PASSWORD '<LAB_PASSWORD>';"
```

Observed:

```text
CREATE ROLE
```

A dedicated application database was created:

```bash
sudo -u postgres createdb -O inc010_app inc010_db
```

The database was owned by:

```text
inc010_app
```

---

## Baseline Application Connection

A TCP connection was tested through localhost:

```bash
PGPASSWORD='<LAB_PASSWORD>' \
psql -h 127.0.0.1 \
-U inc010_app \
-d inc010_db \
-c "SELECT current_user, current_database();"
```

Observed:

```text
 current_user | current_database
--------------+-----------------
 inc010_app   | inc010_db
(1 row)
```

This proved that:

```text
PostgreSQL was reachable
TCP port 5432 was functioning
Authentication succeeded
The application role was valid
The application database was accessible
```

---

## Authentication Configuration Discovery

The active PostgreSQL host-based authentication file was identified:

```bash
sudo -u postgres psql -Atqc "SHOW hba_file;"
```

Observed:

```text
/etc/postgresql/16/main/pg_hba.conf
```

The effective non-comment authentication rules were inspected:

```bash
sudo grep -vE '^[[:space:]]*(#|$)' \
/etc/postgresql/16/main/pg_hba.conf
```

Relevant localhost rule:

```text
host    all    all    127.0.0.1/32    scram-sha-256
```

This rule allowed authenticated TCP connections from localhost.

---

## Configuration Backup

Before modifying authentication policy, the active configuration was backed up:

```bash
sudo cp \
/etc/postgresql/16/main/pg_hba.conf \
/etc/postgresql/16/main/pg_hba.conf.inc010.bak
```

This provided a direct rollback path before introducing the controlled failure.---

## Controlled Connection Failure

A targeted reject rule was inserted at the top of `pg_hba.conf`:

```bash
sudo sed -i \
'1ihost    inc010_db    inc010_app    127.0.0.1/32    reject' \
/etc/postgresql/16/main/pg_hba.conf
```

The beginning of the file was inspected:

```bash
sudo head -n 8 /etc/postgresql/16/main/pg_hba.conf
```

Observed first rule:

```text
host    inc010_db    inc010_app    127.0.0.1/32    reject
```

Because `pg_hba.conf` is evaluated from top to bottom, this targeted rule matched before the broader localhost authentication rule.

---

## Configuration Validation Before Reload

PostgreSQL's parsed HBA rules were inspected:

```bash
sudo -u postgres psql -c \
"SELECT line_number,type,database,user_name,address,auth_method,error
 FROM pg_hba_file_rules
 WHERE line_number <= 8 OR error IS NOT NULL;"
```

Observed:

```text
line_number | type | database    | user_name      | address   | auth_method | error
------------+------+-------------+----------------+-----------+-------------+------
1           | host | {inc010_db} | {inc010_app}   | 127.0.0.1 | reject      |
```

The `error` field was empty.

This confirmed that PostgreSQL considered the new rule syntactically valid before the configuration was activated.

---

## Failure Activation

PostgreSQL configuration was reloaded:

```bash
sudo systemctl reload postgresql
```

The PostgreSQL cluster was checked immediately afterward:

```bash
sudo pg_lsclusters
```

Observed:

```text
16  main  5432  online
```

Port 5432 was also checked:

```bash
sudo ss -ltnp | grep 5432
```

Observed:

```text
127.0.0.1:5432
```

This proved the PostgreSQL server remained available after the configuration reload.

---

## Application Connection Failure Reproduction

The exact same application connection used during baseline validation was retried:

```bash
PGPASSWORD='<LAB_PASSWORD>' \
psql -h 127.0.0.1 \
-U inc010_app \
-d inc010_db \
-c "SELECT current_user, current_database();"
```

Observed:

```text
psql: error: connection to server at "127.0.0.1", port 5432 failed:
FATAL: pg_hba.conf rejects connection for host "127.0.0.1",
user "inc010_app",
database "inc010_db", SSL encryption

connection to server at "127.0.0.1", port 5432 failed:
FATAL: pg_hba.conf rejects connection for host "127.0.0.1",
user "inc010_app",
database "inc010_db", no encryption
```

The application could no longer establish a database session.

---

## PostgreSQL Log Evidence

The PostgreSQL log was inspected:

```bash
sudo tail -n 20 \
/var/log/postgresql/postgresql-16-main.log
```

The log confirmed the configuration reload:

```text
received SIGHUP, reloading configuration files
```

It then recorded the rejected application connections:

```text
inc010_app@inc010_db FATAL:
pg_hba.conf rejects connection for host "127.0.0.1",
user "inc010_app",
database "inc010_db"
```

Both SSL and non-SSL connection attempts were rejected.

This independently confirmed that the failure originated from PostgreSQL host-based authentication policy.

---

## Impact Analysis

During the incident:

```text
PostgreSQL process       HEALTHY
PostgreSQL cluster       ONLINE
TCP port 5432            LISTENING
Application credentials  VALID
Application database     EXISTS
Application connection   REJECTED
```

The problem was therefore not:

```text
PostgreSQL service outage
database process crash
closed TCP port
missing application database
invalid application password
database role removal
```

The failure was isolated to connection authorization.

---

## Root Cause

The root cause was the targeted `pg_hba.conf` rule:

```text
host    inc010_db    inc010_app    127.0.0.1/32    reject
```

Because PostgreSQL evaluates HBA rules sequentially, this rule matched the application connection before the normal localhost rule:

```text
host    all    all    127.0.0.1/32    scram-sha-256
```

Failure chain:

```text
Application attempts TCP connection
→ PostgreSQL accepts connection on port 5432
→ pg_hba.conf rules evaluated
→ targeted reject rule matches
→ authentication is not attempted
→ PostgreSQL rejects connection
→ application receives FATAL error
```

This distinction is important because the server itself remained healthy throughout the incident.

---

## Recovery

The original `pg_hba.conf` was restored from the backup:

```bash
sudo cp \
/etc/postgresql/16/main/pg_hba.conf.inc010.bak \
/etc/postgresql/16/main/pg_hba.conf
```

The effective rules were inspected again:

```bash
sudo grep -vE '^[[:space:]]*(#|$)' \
/etc/postgresql/16/main/pg_hba.conf
```

The targeted reject rule was no longer present.

The normal localhost rule was restored:

```text
host    all    all    127.0.0.1/32    scram-sha-256
```

PostgreSQL configuration was reloaded:

```bash
sudo systemctl reload postgresql
```

---

## Recovery Validation

The same application connection was tested again:

```bash
PGPASSWORD='<LAB_PASSWORD>' \
psql -h 127.0.0.1 \
-U inc010_app \
-d inc010_db \
-c "SELECT current_user, current_database();"
```

Observed:

```text
 current_user | current_database
--------------+-----------------
 inc010_app   | inc010_db
(1 row)
```

The exact workload that failed during the incident now succeeded without changing the role password or database.

This confirmed the authentication policy was the root cause.

---

## Final PostgreSQL Health Validation

The cluster was checked:

```bash
sudo pg_lsclusters
```

Observed:

```text
16  main  5432  online
```

Port 5432 was checked:

```bash
sudo ss -ltnp | grep 5432
```

Observed:

```text
127.0.0.1:5432
```

PostgreSQL therefore remained healthy after recovery.

---

## Cleanup

The temporary test database was removed:

```bash
sudo -u postgres dropdb inc010_db
```

The temporary test role was removed:

```bash
sudo -u postgres psql -c \
"DROP ROLE inc010_app;"
```

Observed:

```text
DROP ROLE
```

The temporary HBA backup was removed:

```bash
sudo rm \
/etc/postgresql/16/main/pg_hba.conf.inc010.bak
```

---

## Cleanup Validation

The test database was checked:

```bash
sudo -u postgres psql -Atqc \
"SELECT datname FROM pg_database WHERE datname='inc010_db';"
```

Observed:

```text
No output
```

The test role was checked:

```bash
sudo -u postgres psql -Atqc \
"SELECT rolname FROM pg_roles WHERE rolname='inc010_app';"
```

Observed:

```text
No output
```

The PostgreSQL cluster was checked one final time:

```bash
sudo pg_lsclusters
```

Observed:

```text
16  main  5432  online
```

The temporary incident objects were removed while PostgreSQL itself remained installed and operational.

---

## Technical Findings

1. A database connection failure does not automatically mean the database server is down.
2. Service state, cluster state, and TCP listener state should be validated before assuming an outage.
3. `pg_hba.conf` controls PostgreSQL client connection authorization.
4. HBA rules are evaluated sequentially from top to bottom.
5. A specific reject rule can block one application without affecting the database server or other clients.
6. `pg_hba_file_rules` can validate parsed HBA configuration before a reload.
7. An empty `error` field indicates the rule parsed successfully.
8. `systemctl reload postgresql` applies authentication changes without requiring a database restart.
9. PostgreSQL logs provide direct evidence of HBA rejection.
10. Reproducing the exact same application connection before and after recovery provides strong validation.
11. Configuration backups should be created before modifying authentication policy.
12. Cleanup should remove only temporary incident objects and preserve the healthy database service.

---

## Support Troubleshooting Method

The workflow used was:

```text
Check PostgreSQL availability
→ install PostgreSQL
→ establish healthy baseline
→ create application role and database
→ validate TCP connection
→ identify active pg_hba.conf
→ back up configuration
→ add targeted reject rule
→ validate rule parsing
→ reload PostgreSQL
→ reproduce application failure
→ confirm database service remains healthy
→ inspect PostgreSQL logs
→ identify HBA policy as root cause
→ restore configuration
→ reload PostgreSQL
→ retry exact application connection
→ validate recovery
→ remove temporary test objects
→ confirm final database health
```

---

## Final Status

```text
PostgreSQL package installation      PASS
Cluster baseline validation          PASS
Port 5432 baseline validation        PASS
Application role creation            PASS
Application database creation        PASS
Baseline TCP connection              PASS
HBA file discovery                   PASS
Configuration backup                 PASS
Targeted reject rule creation        PASS
HBA rule syntax validation           PASS
Configuration reload                 PASS
Connection failure reproduction      PASS
Cluster health during failure        PASS
Port health during failure           PASS
PostgreSQL log validation            PASS
Root cause identification            PASS
Configuration restoration            PASS
Application connection recovery      PASS
Post-recovery cluster validation     PASS
Post-recovery port validation        PASS
Database cleanup                     PASS
Role cleanup                         PASS
Backup cleanup                       PASS
Final PostgreSQL health check        PASS
```

**INC010 status: RESOLVED / VALIDATED**

---

# Phase 2 — Multi-VM PostgreSQL Policy Failure

## Upgrade Objective

The original PostgreSQL incident was extended from a single-host troubleshooting exercise into a cross-VM application/database failure.

Environment:

- `vm-web-01` — `192.168.100.10`
  - Nginx
  - PHP-FPM
  - application health endpoint
- `vm-db-01` — `192.168.100.20`
  - PostgreSQL 14
  - database: `enterprise_app`
  - role: `enterprise_app`
- private network: `192.168.100.0/24`

Application dependency:

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
```

## Healthy Baseline

Before the failure, the application successfully connected from the web VM to PostgreSQL and returned:

```text
HTTP 200
```

The working access rule was:

```text
host enterprise_app enterprise_app 192.168.100.10/32 scram-sha-256
```

## Failure Injection

A PostgreSQL HBA policy was introduced that rejected the application host.

PostgreSQL itself remained active and TCP port `5432` remained reachable.

The web application then degraded to:

```text
HTTP 503
{"status":"degraded","database":"unreachable"}
```

## Evidence

PostgreSQL logs identified the policy failure directly:

```text
FATAL: pg_hba.conf rejects connection for host "192.168.100.10",
user "enterprise_app", database "enterprise_app"
```

This ruled out a database-process outage and isolated the issue to PostgreSQL access control.

## Recovery

The known-good `pg_hba.conf` configuration was restored and PostgreSQL was reloaded.

The application recovered to:

```text
HTTP 200
{"status":"ok","database":"enterprise_app","db_user":"enterprise_app","db_server":"192.168.100.20/32"}
```

## Phase 2 Troubleshooting Flow

```text
HTTP failure
→ verify Nginx/PHP-FPM
→ verify TCP/5432
→ verify PostgreSQL active
→ inspect PostgreSQL logs
→ identify pg_hba.conf rejection
→ restore policy
→ reload PostgreSQL
→ validate HTTP 200
```

## Phase 2 Result

This upgrade demonstrates that successful network connectivity and an active PostgreSQL service do not guarantee application-level database access.

The incident now covers cross-VM troubleshooting across application health, Linux services, TCP connectivity, PostgreSQL authentication policy, server logs, configuration rollback, and recovery validation.
