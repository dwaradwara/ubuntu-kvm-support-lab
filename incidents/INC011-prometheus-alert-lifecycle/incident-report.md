# INC011 — Prometheus Alert Lifecycle and Target Recovery

## Summary

A controlled Prometheus alert lifecycle was created, triggered, investigated, recovered, and cleaned up on the Ubuntu KVM guest.

Prometheus was not initially installed, so Prometheus and the bundled node exporter were installed and validated first.

A healthy monitoring baseline was confirmed:

```text
Prometheus service       → active
Prometheus readiness     → ready
Port 9090                → listening
Node exporter service    → active
Port 9100                → listening
```

The existing Prometheus configuration already contained a scrape job for:

```text
job: node
target: localhost:9100
```

A dedicated alert rule was created:

```text
NodeExporterDown
```

with the expression:

```promql
up{job="node"} == 0
```

and:

```text
for: 15s
severity: critical
incident: INC011
```

The rule and full Prometheus configuration were validated with `promtool` before reload.

Node exporter was then stopped intentionally.

Prometheus continued running normally but its `node` target became unavailable.

The underlying metric changed to:

```text
up{job="node"} = 0
```

and the alert entered:

```text
state: firing
```

The node exporter service was then restarted.

Prometheus detected the target recovery:

```text
up{job="node"} = 1
```

and the alert disappeared from the active alert set:

```text
NodeExporterDown resolved
```

The temporary INC011 alert rule was removed and the original Prometheus configuration was restored.

Final validation confirmed:

```text
Prometheus                → active
Prometheus node exporter  → active
Prometheus readiness      → ready
INC011 alert rule         → removed
Configuration syntax      → valid
```

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

## Initial Prometheus Baseline

Prometheus availability was checked:

```bash
command -v prometheus || echo "prometheus not installed"
```

Observed:

```text
prometheus not installed
```

The Prometheus systemd service was checked:

```bash
systemctl status prometheus --no-pager -l
```

Observed:

```text
Unit prometheus.service could not be found.
```

Port 9090 was checked:

```bash
sudo ss -ltnp | grep 9090 || \
echo "Nothing listening on port 9090"
```

Observed:

```text
Nothing listening on port 9090
```

The available package was checked:

```bash
apt-cache policy prometheus
```

Observed candidate:

```text
2.45.3+ds-2ubuntu0.3
```

This confirmed that Prometheus was not installed but was available from the configured Ubuntu repositories.

---

## Prometheus Installation

Prometheus was installed:

```bash
sudo apt-get install -y prometheus
```

After installation, Prometheus service startup logs showed successful initialization of the TSDB and configuration.

Relevant startup evidence included:

```text
Loading configuration file
Completed loading of configuration file
Server is ready to receive web requests.
Starting rule manager...
```

The Prometheus listener was checked:

```bash
sudo ss -ltnp | grep 9090
```

Observed:

```text
*:9090
```

Prometheus readiness was checked:

```bash
curl -s http://127.0.0.1:9090/-/ready
```

Observed:

```text
Prometheus Server is Ready.
```

This established the healthy Prometheus baseline.

---

## Existing Monitoring Target

The Prometheus configuration was inspected:

```bash
sudo cat /etc/prometheus/prometheus.yml
```

The existing scrape configuration contained:

```yaml
- job_name: 'prometheus'
  scrape_interval: 5s
  scrape_timeout: 5s

  static_configs:
    - targets: ['localhost:9090']
```

and:

```yaml
- job_name: node
  static_configs:
    - targets: ['localhost:9100']
```

This meant a local node exporter target was already configured.

---

## Node Exporter Validation

Node exporter state was checked:

```bash
systemctl status prometheus-node-exporter --no-pager -l
```

Observed:

```text
Active: active (running)
```

Startup output showed:

```text
Listening on address=[::]:9100
TLS is disabled.
```

The service was therefore available to Prometheus on:

```text
localhost:9100
```

This existing monitored target was selected for INC011 instead of creating an unnecessary additional service.

---

## Prometheus Configuration Backup

Before modifying Prometheus configuration, a backup was created:

```bash
sudo cp \
/etc/prometheus/prometheus.yml \
/etc/prometheus/prometheus.yml.inc011.bak
```

The backup was verified under:

```text
/etc/prometheus/prometheus.yml.inc011.bak
```

The available configuration files were inspected:

```bash
ls -la /etc/prometheus
```

`promtool` availability was also checked:

```bash
command -v promtool
```

Observed:

```text
/usr/bin/promtool
```

This provided a safe way to validate rule and configuration syntax before applying changes.

---

## Rule File Configuration

The active Prometheus configuration already contained:

```yaml
rule_files:
```

with example rule entries commented out.

The relevant configuration structure was inspected:

```bash
sudo grep -nE \
'^[[:space:]]*rule_files:|^[[:space:]]*scrape_configs:' \
/etc/prometheus/prometheus.yml
```

This confirmed that the existing `rule_files` section could be reused without restructuring the entire configuration.

---

## INC011 Alert Rule

A dedicated rule file was created:

```bash
sudo tee /etc/prometheus/inc011_rules.yml >/dev/null <<'EOF'
groups:
  - name: inc011-alerts
    rules:
      - alert: NodeExporterDown
        expr: up{job="node"} == 0
        for: 15s
        labels:
          severity: critical
          incident: INC011
        annotations:
          summary: "Node exporter target is down"
          description: "Prometheus cannot scrape the node exporter target for more than 15 seconds."
EOF
```

The rule detects when the `node` scrape target reports:

```text
up = 0
```

continuously for at least:

```text
15 seconds
```

---

## Rule File Registration

The new rule file was added below the existing `rule_files:` section:

```bash
sudo sed -i \
'/^rule_files:/a\  - "/etc/prometheus/inc011_rules.yml"' \
/etc/prometheus/prometheus.yml
```

The configuration was checked:

```bash
sudo grep -A4 -n '^rule_files:' \
/etc/prometheus/prometheus.yml
```

Observed:

```text
rule_files:
  - "/etc/prometheus/inc011_rules.yml"
```

---

## Rule Syntax Validation

The rule file was validated before reload:

```bash
promtool check rules \
/etc/prometheus/inc011_rules.yml
```

Observed:

```text
SUCCESS: 1 rules found
```

The entire Prometheus configuration was then validated:

```bash
promtool check config \
/etc/prometheus/prometheus.yml
```

Observed:

```text
SUCCESS: /etc/prometheus/prometheus.yml is valid prometheus config file syntax
```

The rule file was also loaded successfully during full configuration validation:

```text
SUCCESS: 1 rules found
```

This confirmed that both the alert rule and complete Prometheus configuration were valid before activation.---

## Alert Rule Activation

The validated Prometheus configuration was reloaded:

```bash
sudo systemctl reload prometheus
```

Prometheus remained healthy after the reload.

The alert rule was confirmed as loaded through the Prometheus HTTP API:

```bash
curl -s \
http://127.0.0.1:9090/api/v1/rules \
| grep -o '"name":"NodeExporterDown"'
```

Observed:

```text
"name":"NodeExporterDown"
```

This confirmed the rule was active in Prometheus.

---

## Healthy Alert Baseline

Before introducing any failure, the active alert set was checked:

```bash
curl -s \
http://127.0.0.1:9090/api/v1/alerts \
| grep -o '"alertname":"NodeExporterDown"' \
|| echo "NodeExporterDown not firing"
```

Observed:

```text
NodeExporterDown not firing
```

This established the healthy baseline.

At this stage:

```text
Prometheus           → healthy
Node exporter        → healthy
node target          → reachable
NodeExporterDown     → not firing
```

---

## Controlled Target Failure

Node exporter was stopped intentionally:

```bash
sudo systemctl stop prometheus-node-exporter
```

The service state was checked:

```bash
systemctl status \
prometheus-node-exporter \
--no-pager -l
```

Observed:

```text
Active: inactive (dead)
```

The service shutdown completed successfully.

This created the target failure without stopping Prometheus itself.

---

## Prometheus Target Failure Detection

Prometheus continued scraping the configured node target:

```text
localhost:9100
```

Because node exporter was no longer running, the target metric changed.

The `up` metric was queried directly:

```bash
curl -s \
'http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D%22node%22%7D' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)
[(print(r["metric"],"value:",r["value"][1]))
 for r in d["data"]["result"]]
'
```

Observed:

```text
{'__name__': 'up', 'instance': 'localhost:9100', 'job': 'node'} value: 0
```

This proved that Prometheus had detected the scrape target as unavailable.

---

## Alert Firing Validation

The alert rule contained:

```text
for: 15s
```

so the failure had to remain true for at least 15 seconds before moving from pending to firing.

After the target had remained unavailable long enough, the active alert state was queried:

```bash
curl -s \
http://127.0.0.1:9090/api/v1/alerts \
| python3 -c '
import sys,json
d=json.load(sys.stdin)
[(print(
    "alert:",
    a["labels"].get("alertname"),
    "state:",
    a["state"]
))
 for a in d["data"]["alerts"]
 if a["labels"].get("alertname")=="NodeExporterDown"]
'
```

Observed:

```text
alert: NodeExporterDown state: firing
```

This provided direct evidence that the alert lifecycle had reached the firing state.

---

## Failure State Summary

During the controlled incident:

```text
Prometheus service       → active
Prometheus readiness     → ready
Node exporter service    → inactive
Node exporter port 9100  → unavailable
Prometheus node target   → down
up{job="node"}           → 0
NodeExporterDown         → firing
```

The monitoring platform remained healthy while correctly detecting the dependent target failure.

---

## Root Cause

The alert was firing because Prometheus could no longer scrape:

```text
localhost:9100
```

The direct cause was:

```text
prometheus-node-exporter.service stopped
```

Failure chain:

```text
Node exporter service stops
→ port 9100 becomes unavailable
→ Prometheus scrape fails
→ up{job="node"} becomes 0
→ condition persists for 15 seconds
→ NodeExporterDown enters firing state
```

The alert was therefore behaving exactly according to its configured expression and duration.

---

## Recovery

Node exporter was restarted:

```bash
sudo systemctl start prometheus-node-exporter
```

The service was checked:

```bash
systemctl status \
prometheus-node-exporter \
--no-pager -l
```

Observed:

```text
Active: active (running)
```

Startup logs confirmed the exporter was again listening on:

```text
[::]:9100
```

---

## Metric Recovery Validation

Prometheus was given time to perform another scrape.

The `up` metric was queried again:

```bash
curl -s \
'http://127.0.0.1:9090/api/v1/query?query=up%7Bjob%3D%22node%22%7D' \
| python3 -c '
import sys,json
d=json.load(sys.stdin)
[(print(r["metric"],"value:",r["value"][1]))
 for r in d["data"]["result"]]
'
```

Observed:

```text
{'__name__': 'up', 'instance': 'localhost:9100', 'job': 'node'} value: 1
```

This proved that Prometheus could successfully scrape the node target again.

---

## Alert Resolution Validation

The active alert set was queried again:

```bash
curl -s \
http://127.0.0.1:9090/api/v1/alerts \
| python3 -c '
import sys,json
d=json.load(sys.stdin)
a=[
    x for x in d["data"]["alerts"]
    if x["labels"].get("alertname")=="NodeExporterDown"
]
print(
    "NodeExporterDown resolved"
    if not a
    else [(x["state"],x["labels"]) for x in a]
)
'
```

Observed:

```text
NodeExporterDown resolved
```

This confirmed that once the scrape target recovered and the alert expression became false, the alert was removed from the active alert set.

---

## Prometheus Health After Recovery

Prometheus readiness was checked:

```bash
curl -s http://127.0.0.1:9090/-/ready
```

Observed:

```text
Prometheus Server is Ready.
```

Prometheus therefore remained healthy throughout both the failure and recovery.

---

## Temporary Alert Cleanup

The original Prometheus configuration was restored:

```bash
sudo cp \
/etc/prometheus/prometheus.yml.inc011.bak \
/etc/prometheus/prometheus.yml
```

The temporary rule file was removed:

```bash
sudo rm /etc/prometheus/inc011_rules.yml
```

The temporary configuration backup was then removed:

```bash
sudo rm \
/etc/prometheus/prometheus.yml.inc011.bak
```

---

## Restored Configuration Validation

The restored Prometheus configuration was checked:

```bash
promtool check config \
/etc/prometheus/prometheus.yml
```

Observed:

```text
SUCCESS: /etc/prometheus/prometheus.yml is valid prometheus config file syntax
```

Prometheus was then reloaded:

```bash
sudo systemctl reload prometheus
```

---

## Final Health Validation

Prometheus readiness:

```bash
curl -s http://127.0.0.1:9090/-/ready
```

Observed:

```text
Prometheus Server is Ready.
```

Prometheus service state:

```bash
systemctl is-active prometheus
```

Observed:

```text
active
```

Node exporter service state:

```bash
systemctl is-active prometheus-node-exporter
```

Observed:

```text
active
```

The temporary alert rule was checked:

```bash
curl -s \
http://127.0.0.1:9090/api/v1/rules \
| grep -o '"name":"NodeExporterDown"' \
|| echo "INC011 rule removed"
```

Observed:

```text
INC011 rule removed
```

This confirmed the lab was returned to a clean healthy state.

---

## Technical Findings

1. Prometheus alerting should be validated from both the rule state and the underlying metric.
2. Seeing an alert name in the API does not by itself prove that the alert is firing.
3. Alerts using a `for` duration can remain pending before entering the firing state.
4. `up{job="node"} = 0` directly indicates that Prometheus cannot successfully scrape the configured target.
5. `up{job="node"} = 1` confirms target recovery.
6. A monitored target can fail while Prometheus itself remains completely healthy.
7. Prometheus HTTP APIs provide direct evidence for target health and alert state.
8. `promtool check rules` should be used before loading a new rule file.
9. `promtool check config` should be used before reloading Prometheus configuration.
10. Configuration reloads avoid unnecessary Prometheus restarts.
11. A monitoring incident should include baseline, failure, firing, recovery, and cleanup evidence.
12. Temporary alert rules should be removed after controlled validation.

---

## Support Troubleshooting Method

The workflow used was:

```text
Check Prometheus availability
→ install Prometheus
→ validate Prometheus readiness
→ inspect existing scrape jobs
→ validate node exporter
→ back up Prometheus configuration
→ create dedicated alert rule
→ validate rule syntax
→ validate complete configuration
→ reload Prometheus
→ confirm rule loaded
→ establish healthy alert baseline
→ stop monitored target
→ confirm target service failure
→ verify up metric equals 0
→ wait through alert duration
→ confirm alert state is firing
→ restart monitored target
→ verify up metric returns to 1
→ confirm alert resolution
→ confirm Prometheus stayed healthy
→ restore original configuration
→ remove temporary rule
→ validate final configuration
→ confirm both services active
→ confirm temporary alert removed
```

---

## Final Status

```text
Prometheus package installation      PASS
Prometheus startup validation        PASS
Port 9090 validation                 PASS
Readiness endpoint validation        PASS
Node exporter discovery              PASS
Node exporter baseline               PASS
Configuration backup                 PASS
Alert rule creation                  PASS
Rule syntax validation               PASS
Prometheus config validation         PASS
Rule activation                      PASS
Healthy alert baseline               PASS
Controlled target shutdown           PASS
Node exporter failure validation     PASS
up metric failure validation         PASS
Alert firing validation              PASS
Root cause identification            PASS
Node exporter recovery               PASS
up metric recovery validation        PASS
Alert resolution validation          PASS
Prometheus post-recovery health      PASS
Original config restoration          PASS
Temporary rule removal               PASS
Final config validation              PASS
Prometheus final state               PASS
Node exporter final state            PASS
Final rule cleanup validation        PASS
```

**INC011 status: RESOLVED / VALIDATED**
