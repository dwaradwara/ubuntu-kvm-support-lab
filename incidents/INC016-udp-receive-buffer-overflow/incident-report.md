# INC016 — UDP Receive Buffer Overflow and Packet Drop Recovery

## Summary

A controlled UDP receive-buffer overflow was reproduced and recovered on the Ubuntu KVM guest.

The goal was to demonstrate application-level packet loss caused by an undersized receive buffer without disrupting the VM network, SSH, Nginx, PostgreSQL, or monitoring services.

The baseline socket buffer configuration was:

```text
net.core.rmem_default = 212992
net.core.rmem_max     = 212992
net.core.wmem_default = 212992
net.core.wmem_max     = 212992
```

The UDP kernel counters initially showed:

```text
RcvbufErrors = 0
```

A dedicated UDP receiver was created on:

```text
127.0.0.1:9999
```

The receiver explicitly requested:

```text
SO_RCVBUF = 4096
```

Linux reported the effective receive buffer as:

```text
SO_RCVBUF = 8192
```

The receiver intentionally paused for several seconds without consuming packets.

During that pause, a sender transmitted:

```text
50,000 UDP packets
```

with:

```text
1024-byte payloads
```

The receiver eventually processed only:

```text
4 packets
```

The kernel UDP counters then showed:

```text
RcvbufErrors = 49996
```

The full UDP counters confirmed:

```text
InErrors     = 49996
RcvbufErrors = 49996
```

This matched the packet-loss calculation exactly:

```text
50,000 sent
-     4 received
= 49,996 dropped
```

The recovery test used:

```text
SO_RCVBUF = 212992 requested
```

which Linux reported as:

```text
SO_RCVBUF = 425984
```

The recovery receiver consumed packets continuously while the sender transmitted:

```text
10,000 packets
```

Observed:

```text
sent                 = 10000
received             = 10000
new_RcvbufErrors     = 0
```

This proved that the packet loss was caused by receive-buffer exhaustion combined with the application not reading packets fast enough.

After validation, all temporary INC016 scripts and transient services were removed.

Final state:

```text
UDP port 9999             → free
INC016 transient units    → removed
INC016 scripts            → removed
nginx                     → active
postgresql                → active
prometheus                → active
prometheus-node-exporter  → active
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

## Socket Buffer Baseline

The default receive buffer was checked:

```bash
sysctl net.core.rmem_default
```

Observed:

```text
net.core.rmem_default = 212992
```

The maximum receive buffer was checked:

```bash
sysctl net.core.rmem_max
```

Observed:

```text
net.core.rmem_max = 212992
```

The default send buffer was checked:

```bash
sysctl net.core.wmem_default
```

Observed:

```text
net.core.wmem_default = 212992
```

The maximum send buffer was checked:

```bash
sysctl net.core.wmem_max
```

Observed:

```text
net.core.wmem_max = 212992
```

This established the host socket-buffer baseline before INC016.

---

## UDP Counter Baseline

UDP counters were inspected:

```bash
awk '/^Udp:/{print}' /proc/net/snmp
```

Observed:

```text
Udp: InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors SndbufErrors InCsumErrors IgnoredMulti MemErrors
Udp: 173 40 0 213 0 0 0 0 0
```

The important value was:

```text
RcvbufErrors = 0
```

This provided a clean baseline for later comparison.

---

## Python Availability

Python was checked:

```bash
command -v python3
```

Observed:

```text
/usr/bin/python3
```

Python was used for both UDP receiver and sender logic.

---

## UDP Test Port Baseline

Port 9999 was checked:

```bash
sudo ss -lunp | \
grep ':9999' || \
echo "UDP port 9999 free"
```

Observed:

```text
UDP port 9999 free
```

This confirmed the port was available for the test.

---

## Core Service Baseline

Persistent services were checked:

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

This established a baseline that could later be compared against the post-test state.

---

## Safety Design

The test was intentionally confined to:

```text
127.0.0.1
```

rather than an external interface.

This prevented disruption to:

```text
SSH
libvirt networking
Nginx
PostgreSQL
Prometheus
host-to-guest connectivity
```

The incident was designed to stress only a dedicated localhost UDP socket.

---

## Initial Receiver Design

A receiver script was created at:

```text
/tmp/inc016_receiver.py
```

The receiver:

```text
created a UDP socket
requested a 4096-byte receive buffer
bound to 127.0.0.1:9999
paused for 6 seconds
then attempted to consume queued packets
```

The important socket configuration was:

```python
s.setsockopt(
    socket.SOL_SOCKET,
    socket.SO_RCVBUF,
    4096
)
```

The receiver then bound to:

```python
("127.0.0.1", 9999)
```

---

## Linux Effective Receive Buffer

The receiver logged:

```text
SO_RCVBUF = 8192
```

even though the script requested:

```text
4096
```

This reflected Linux socket-buffer accounting behavior.

The effective receive buffer was still intentionally tiny compared with the upcoming packet burst.

---

## Initial Receiver Timing Attempt

The first receiver run completed without any packet burst being sent during its active window.

Observed:

```text
INC016 receiver ready
SO_RCVBUF = 8192
received_after_pause = 0
```

The service then exited successfully.

Because no traffic had been sent during the active period, this run did not reproduce the incident and was not treated as failure evidence.

---

## Controlled Failure Test

A second receiver instance was started:

```text
inc016-receiver2.service
```

The receiver again used:

```text
SO_RCVBUF = 8192
```

and intentionally paused before reading.

A sender then transmitted:

```text
50,000 UDP packets
```

Each packet contained:

```text
1024 bytes
```

Sender logic:

```python
for i in range(50000):
    s.sendto(payload, ("127.0.0.1", 9999))
```

The sender reported:

```text
sent_packets = 50000
```

---

## Failure Receiver Result

The receiver journal showed:

```text
INC016 receiver ready
SO_RCVBUF = 8192
received_after_pause = 4
```

Only four packets survived the burst long enough to be consumed by the application.

This indicated severe receive-buffer overflow.

---

## UDP Receive Buffer Error Counter

After the burst, the `RcvbufErrors` counter was checked.

Observed:

```text
RcvbufErrors_after=49996
```

The counter increased from:

```text
0
```

to:

```text
49996
```

This provided direct kernel-level evidence of socket receive-buffer drops.

---

## Full UDP Counter Evidence

The full UDP counters were checked again:

```bash
awk '/^Udp:/{print}' /proc/net/snmp
```

Observed:

```text
Udp: InDatagrams NoPorts InErrors OutDatagrams RcvbufErrors SndbufErrors InCsumErrors IgnoredMulti MemErrors
Udp: 179 40 49996 50215 49996 0 0 0 0
```

The critical values were:

```text
InErrors     = 49996
RcvbufErrors = 49996
```

This tied the packet-loss event directly to receive-buffer overflow.

---

## Packet Accounting

The test produced:

```text
Packets sent     = 50000
Packets received = 4
```

Calculated packet loss:

```text
50000 - 4 = 49996
```

Observed kernel counter:

```text
RcvbufErrors = 49996
```

The values matched exactly.

This provided unusually strong causal evidence that the missing packets were dropped because the UDP receive buffer overflowed.

---

## Failure State

During the failure:

```text
UDP receiver                → running
Receiver buffer             → 8192 bytes effective
Receiver behavior           → intentionally not reading
Packets sent                → 50000
Packets received            → 4
RcvbufErrors increase       → 49996
InErrors increase           → 49996
Core services               → unaffected
```

The failure was therefore isolated to the test socket and application-consumption behavior.---

## Recovery Design

The recovery test changed two conditions:

```text
Receive buffer size       → increased
Application consumption   → continuous
```

The recovery receiver requested:

```text
SO_RCVBUF = 212992
```

Linux reported the effective value as:

```text
SO_RCVBUF = 425984
```

The receiver also began reading packets immediately instead of pausing.

The goal was to prove that packet loss stopped when the application had enough buffer capacity and consumed traffic continuously.

---

## First Recovery Attempt

An initial recovery receiver was started as a transient service.

The sender transmitted:

```text
10000 packets
```

The receiver journal showed:

```text
expected = 10000
received = 0
```

The kernel counter remained:

```text
RcvbufErrors = 49996
```

Because the receiver did not process the sender traffic during that run, the attempt was not accepted as valid recovery evidence.

The incident was therefore not considered resolved at that point.

---

## Deterministic Recovery Test

To remove timing ambiguity, a single Python recovery program was created:

```text
/tmp/inc016_recovery_test.py
```

The program:

```text
created the receiver
started a receive thread
waited briefly for receiver readiness
sent 10000 UDP packets
waited for the receiver thread to finish
read RcvbufErrors before and after
```

This ensured sender and receiver timing were controlled inside one process.

---

## Recovery Receiver Configuration

The recovery receiver used:

```python
receiver.setsockopt(
    socket.SOL_SOCKET,
    socket.SO_RCVBUF,
    212992
)
```

The effective socket buffer reported by Linux was:

```text
SO_RCVBUF = 425984
```

This was substantially larger than the failure configuration:

```text
Failure effective buffer  → 8192
Recovery effective buffer → 425984
```

---

## Recovery Traffic Pattern

The recovery sender transmitted:

```text
10000 UDP packets
```

with:

```text
1024-byte payloads
```

A small pacing delay was introduced periodically:

```python
if i % 100 == 0:
    time.sleep(0.002)
```

This created a controlled sustained stream rather than an intentionally destructive burst.

---

## Recovery Counter Baseline

Before the recovery test:

```text
RcvbufErrors_before = 49996
```

This value was expected because `/proc/net/snmp` counters are cumulative.

The recovery test did not attempt to reset the kernel counter.

Instead, success was measured by whether the counter increased further.

---

## Recovery Result

The deterministic recovery test reported:

```text
SO_RCVBUF = 425984
RcvbufErrors_before = 49996
sent = 10000
received = 10000
RcvbufErrors_after = 49996
new_RcvbufErrors = 0
```

This proved:

```text
All 10000 packets received
No new receive-buffer errors
No additional packet loss
```

---

## Before / Failure / Recovery Comparison

### Baseline

```text
RcvbufErrors           → 0
UDP port 9999          → free
Core services          → active
```

### Failure

```text
Effective SO_RCVBUF    → 8192
Receiver behavior      → paused
Packets sent           → 50000
Packets received       → 4
New RcvbufErrors       → 49996
```

### Recovery

```text
Effective SO_RCVBUF    → 425984
Receiver behavior      → continuously reading
Packets sent           → 10000
Packets received       → 10000
New RcvbufErrors       → 0
```

This established a complete:

```text
healthy baseline
→ receive-buffer overflow
→ packet-loss evidence
→ corrected receiver behavior
→ zero-new-drop recovery
```

lifecycle.

---

## Root Cause

The root cause was a combination of:

```text
undersized UDP receive buffer
+
application not consuming packets quickly enough
```

The failure chain was:

```text
UDP socket created
→ receive buffer limited to very small size
→ receiver pauses for several seconds
→ sender transmits 50000 packets rapidly
→ socket receive queue fills
→ kernel cannot enqueue additional datagrams
→ UDP packets dropped
→ RcvbufErrors increases
→ application later receives only a few queued packets
```

The root cause was therefore not:

```text
Network interface outage
Kernel network stack failure
SSH interruption
Firewall block
Port conflict
Nginx failure
PostgreSQL failure
Prometheus failure
```

---

## Why RcvbufErrors Was the Key Metric

`RcvbufErrors` in:

```text
/proc/net/snmp
```

counts UDP datagrams dropped because the receive socket buffer could not accept them.

The failure test produced:

```text
RcvbufErrors = 49996
```

which matched:

```text
50000 sent - 4 received = 49996
```

This made `RcvbufErrors` the strongest direct kernel metric for the incident.

---

## Why InErrors Also Increased

The UDP counters showed:

```text
InErrors = 49996
RcvbufErrors = 49996
```

`InErrors` includes UDP receive failures more broadly.

Because the values matched exactly in this test, the observed receive errors were attributable to receive-buffer overflow.

---

## Why the Counter Was Not Reset

The kernel UDP counters are cumulative.

After the failure:

```text
RcvbufErrors = 49996
```

The recovery test therefore validated:

```text
new_RcvbufErrors = 0
```

rather than trying to force the system-wide counter back to zero.

This is the correct operational interpretation of cumulative network counters.

---

## Recovery Strategy

The recovery was not a single arbitrary sysctl change.

The test demonstrated two practical fixes:

```text
Increase receive-buffer capacity
Consume queued packets continuously
```

The recovery receiver used the host's normal maximum requested receive buffer:

```text
212992
```

and read continuously.

This eliminated new receive-buffer drops during the validation stream.

---

## Operational Interpretation

A UDP service can appear healthy at the process level while silently dropping packets.

For example:

```text
process running
socket bound
port listening
```

does not guarantee:

```text
application receiving all traffic
```

UDP has no retransmission guarantee at the protocol level.

Application-side and kernel socket-buffer metrics must therefore be inspected when packet loss is suspected.

---

## Cleanup

All temporary INC016 scripts were removed:

```bash
sudo rm -f \
/tmp/inc016_receiver.py \
/tmp/inc016_receiver_recovery.py \
/tmp/inc016_recovery_test.py
```

---

## UDP Port Cleanup Validation

Port 9999 was checked:

```bash
sudo ss -lunp | \
grep ':9999' || \
echo "UDP port 9999 free"
```

Observed:

```text
UDP port 9999 free
```

This confirmed that no INC016 receiver remained active.

---

## Transient Unit Cleanup Validation

Systemd units were checked:

```bash
systemctl list-units --all | \
grep inc016 || \
echo "INC016 transient units removed"
```

Observed:

```text
INC016 transient units removed
```

This confirmed that the temporary receiver services had been cleared.

---

## Script Cleanup Validation

The temporary files were checked:

```bash
ls -l \
/tmp/inc016_receiver.py \
/tmp/inc016_receiver_recovery.py \
/tmp/inc016_recovery_test.py \
2>&1 || true
```

Observed:

```text
No such file or directory
```

for all three files.

This confirmed complete script cleanup.

---

## Final Core Service Validation

The persistent services were checked:

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

This confirmed that the localhost UDP stress test did not affect the base lab services.

---

## Final State

Temporary INC016 resources:

```text
UDP receiver services      → removed
UDP test scripts           → removed
UDP port 9999              → free
```

Persistent environment:

```text
nginx                      → active
postgresql                 → active
prometheus                 → active
prometheus-node-exporter   → active
```

Kernel UDP counters remained cumulative, including the documented:

```text
RcvbufErrors = 49996
```

from the controlled failure test.

---

## Technical Findings

1. UDP packet loss can occur even when the receiving process is running normally.
2. A bound UDP socket does not prove the application is consuming packets fast enough.
3. `RcvbufErrors` is a strong indicator of UDP receive-buffer overflow.
4. `InErrors` should be reviewed alongside `RcvbufErrors`.
5. A very small `SO_RCVBUF` can make a service extremely vulnerable to short packet bursts.
6. Application read rate matters as much as buffer size.
7. UDP provides no built-in retransmission guarantee.
8. Kernel UDP counters are cumulative and should be compared using deltas.
9. A recovery test should validate zero new errors, not expect cumulative counters to reset.
10. Localhost is useful for safely reproducing socket-buffer problems without disrupting external connectivity.
11. Exact sent-versus-received packet accounting provides strong causal evidence.
12. A failed recovery attempt should not be treated as successful merely because error counters did not increase.
13. Deterministic sender/receiver coordination removes timing ambiguity.
14. Larger receive buffers can absorb burst traffic more effectively.
15. Continuous packet consumption prevents queue buildup.
16. Core-service validation should follow any network stress test.
17. Packet-loss troubleshooting should combine application evidence with kernel counters.

---

## Support Troubleshooting Method

The workflow used was:

```text
Inspect receive-buffer defaults
→ inspect send-buffer defaults
→ capture UDP counter baseline
→ confirm Python availability
→ confirm UDP test port free
→ confirm core services healthy
→ create isolated localhost UDP receiver
→ apply intentionally tiny receive buffer
→ validate effective SO_RCVBUF
→ observe first timing attempt
→ reject invalid first attempt
→ restart controlled receiver
→ send 50000-packet burst
→ capture receiver count
→ capture RcvbufErrors delta
→ capture full UDP counters
→ calculate packet loss
→ match packet loss to RcvbufErrors
→ identify receive-buffer overflow
→ design recovery receiver
→ increase receive buffer
→ consume packets continuously
→ reject invalid first recovery attempt
→ create deterministic combined recovery test
→ send 10000 controlled packets
→ validate 10000 received
→ validate zero new RcvbufErrors
→ remove temporary scripts
→ validate UDP port free
→ validate transient units removed
→ validate core services remain active
```

---

## Phase 3 Support Review

### Before / Failure / After Comparison

| Check | Baseline | Failure | Recovery |
| --- | --- | --- | --- |
| UDP test port | free | receiver bound | free after cleanup |
| Receive buffer | normal system baseline | intentionally tiny | increased / healthy |
| Packets sent | 0 test packets | 50000 | 10000 |
| Packets received | N/A | 4 | 10000 |
| RcvbufErrors delta | 0 | 49996 | 0 new errors |
| Packet loss | none measured | 49996 packets | 0 packets |
| Receiver behavior | healthy baseline | delayed consumption | continuous consumption |
| Core services | active | active | active |

### Customer-Facing Symptom

A production customer could describe a similar incident as:

```text
The UDP service is running and the port is listening, but messages are
being lost during traffic bursts. There are no obvious application
crashes or TCP-style connection errors.
```

The support investigation should distinguish process health from
socket-buffer health:

```text
packet loss
→ verify process and socket
→ inspect application receive rate
→ inspect UDP kernel counters
→ compare RcvbufErrors delta
→ inspect receive-buffer sizing
→ reproduce with controlled traffic
→ validate recovery with zero new drops
```

### Example Support Ticket Update

```text
Status: Resolved

The UDP service remained running, but its receive queue overflowed
during burst traffic.

A controlled 50,000-packet test delivered only 4 packets while the
kernel recorded 49,996 new RcvbufErrors. The exact match between
packet loss and receive-buffer errors identified socket receive-buffer
overflow as the root cause.

The recovery receiver used a larger receive buffer and continuously
consumed queued packets.

A deterministic 10,000-packet validation then received all 10,000
packets and produced zero new RcvbufErrors.

Temporary test resources were removed and persistent services remained
healthy.
```

### What I Would Do Differently

1. Capture ISO-8601 timestamps at the baseline, failure, and recovery milestones.
2. Record UDP counters immediately before and immediately after each traffic test.
3. Capture `ss -u -a -n -m` while the queue is actively filling.
4. Record application-level receive counters alongside kernel counters.
5. Use a deterministic sender/receiver harness from the beginning rather than relying on manual timing.
6. Record packet size and approximate packets-per-second for every test.
7. In production, verify whether drops occur at the socket, interface, virtual switch, or upstream network before changing buffer settings.

### Prevention and Operational Controls

Capture UDP receive-error counters:

```bash
awk '/^Udp:/{print}' /proc/net/snmp
```

Inspect UDP socket queues and memory:

```bash
ss -u -a -n -m
```

Inspect receive-buffer defaults and limits:

```bash
sysctl net.core.rmem_default
sysctl net.core.rmem_max
```

For application troubleshooting, also review the socket-level receive
buffer configured through SO_RCVBUF and whether the application is
consuming datagrams quickly enough.

Kernel counters are cumulative, so monitoring should alert on the
rate or delta of receive-buffer errors rather than the absolute
counter value.

Production remediation should address the actual bottleneck:

```text
buffer capacity
application receive rate
CPU scheduling
traffic burst size
or upstream/network loss
```

rather than applying arbitrary global sysctl increases.


### Relevant Documentation

- [Linux kernel: SNMP counter definitions](https://docs.kernel.org/networking/snmp_counter.html)
- [Linux socket API: socket(7)](https://man7.org/linux/man-pages/man7/socket.7.html)
- [Linux UDP protocol: udp(7)](https://man7.org/linux/man-pages/man7/udp.7.html)
- [ss command: ss(8)](https://man7.org/linux/man-pages/man8/ss.8.html)
- [Linux kernel: IP sysctl networking settings](https://docs.kernel.org/networking/ip-sysctl.html)

---

## Final Status

```text
Receive-buffer baseline                 PASS
Send-buffer baseline                    PASS
UDP counter baseline                    PASS
Python availability                     PASS
UDP port baseline                       PASS
Core-service baseline                   PASS
Localhost safety isolation              PASS
Receiver creation                       PASS
Tiny receive-buffer configuration       PASS
Effective buffer validation             PASS
Controlled burst generation             PASS
50000-packet sender validation          PASS
Receiver packet-count validation        PASS
RcvbufErrors reproduction               PASS
InErrors validation                     PASS
Packet-loss accounting                  PASS
Root-cause identification               PASS
Recovery receiver design                PASS
Large receive-buffer validation         PASS
Deterministic recovery test             PASS
10000-packet recovery send              PASS
10000-packet recovery receive           PASS
Zero-new-RcvbufErrors validation         PASS
Script cleanup                          PASS
UDP port cleanup validation             PASS
Transient-unit cleanup validation       PASS
Final core-service validation           PASS
```

**INC016 status: RESOLVED / VALIDATED**
