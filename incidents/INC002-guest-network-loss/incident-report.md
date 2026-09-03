# INC002 — KVM Guest Network Connectivity Loss

| Field | Details |
|---|---|
| Incident ID | INC002 |
| Date | 2026-09-03 |
| Severity | Medium |
| Status | Resolved |
| Environment | Ubuntu 24.04.4 LTS KVM guest |
| Guest Hostname | lab-guest-01 |
| Guest IP | 192.168.122.170 |
| Hypervisor | KVM/QEMU with libvirt |
| Libvirt Network | default |
| Bridge | virbr0 |
| TAP Interface | vnet1 |
| Guest NIC Model | virtio |
| Guest NIC MAC | 52:54:00:b0:a2:8c |

## Scenario

This incident was deliberately created in a self-directed Ubuntu KVM support lab to simulate a customer-reported virtual machine network outage.

The Ubuntu guest remained powered on and its virtual NIC remained configured, but the guest lost network connectivity after the host-side TAP interface was administratively disabled.

The objective was to isolate whether the failure originated from the guest configuration, libvirt network, Linux bridge, or host-side TAP interface before performing recovery.

---

## Network Architecture

The guest used the libvirt `default` NAT network.

The observed network path was:

    ubuntu-guest-01
          |
       virtio NIC
          |
        vnet1
          |
        virbr0
          |
    libvirt default network
          |
         NAT
          |
    host networking
          |
       Internet

The libvirt network configuration showed:

    Bridge: virbr0
    Gateway: 192.168.122.1
    Subnet: 192.168.122.0/24
    DHCP range: 192.168.122.2 - 192.168.122.254
    Forward mode: NAT

The guest IP address `192.168.122.170` was within the configured DHCP range.

---

## Healthy Baseline

Before introducing the failure, the VM interface mapping was verified:

    virsh -c qemu:///system domiflist ubuntu-guest-01

Observed result:

    Interface   Type     Source   Model    MAC
    vnet1       bridge   virbr0   virtio   52:54:00:b0:a2:8c

The Linux bridge configuration was also checked:

    brctl show

Observed result:

    bridge name   bridge id          STP enabled   interfaces
    virbr0        8000.5254007e7a9f  yes           vnet1

The TAP interface was confirmed operational:

    ip link show vnet1

Observed state:

    <BROADCAST,MULTICAST,UP,LOWER_UP>
    master virbr0
    state UNKNOWN

For this TAP interface, `UP` and `LOWER_UP` confirmed that the host-side virtual link was operational.

Guest connectivity to the libvirt gateway was also verified successfully:

    ping -c 4 192.168.122.1

Observed result:

    4 packets transmitted, 4 received, 0% packet loss

The network was therefore confirmed healthy before fault injection.

---

## Fault Injection

The host-side TAP interface was deliberately disabled:

    sudo ip link set vnet1 down

The interface state was checked again:

    ip link show vnet1

Observed result:

    vnet1: <BROADCAST,MULTICAST>
    master virbr0
    state DOWN

The `UP` and `LOWER_UP` flags were no longer present, confirming that the TAP interface had been administratively disabled.---

## Customer Symptom

After the TAP interface was disabled, the guest lost external network connectivity.

From the guest console, connectivity was tested with:

    ping -c 4 8.8.8.8

Observed result:

    From 192.168.122.170 icmp_seq=1 Destination Host Unreachable
    From 192.168.122.170 icmp_seq=2 Destination Host Unreachable
    From 192.168.122.170 icmp_seq=3 Destination Host Unreachable
    From 192.168.122.170 icmp_seq=4 Destination Host Unreachable

    4 packets transmitted, 0 received, +4 errors, 100% packet loss

The guest remained powered on, but network traffic could no longer leave the VM.

---

## Investigation

The investigation was performed primarily from the KVM host because guest network access was unavailable.

### 1. Verify VM Interface Statistics

The virtual interface statistics were inspected:

    virsh -c qemu:///system domifstat ubuntu-guest-01 vnet1

Observed statistics:

    vnet1 rx_bytes   3106324
    vnet1 rx_packets 7089
    vnet1 rx_errors  0
    vnet1 rx_drop    0
    vnet1 tx_bytes   366395
    vnet1 tx_packets 3315
    vnet1 tx_errors  0
    vnet1 tx_drop    0

The interface had previously carried traffic successfully.

No RX/TX errors or packet drops were recorded.

This reduced the likelihood of packet corruption or an existing error/drop condition.

### 2. Verify VM NIC Configuration

The VM network interface configuration was checked:

    virsh -c qemu:///system domiflist ubuntu-guest-01

Observed result:

    Interface   Type     Source   Model    MAC
    vnet1       bridge   virbr0   virtio   52:54:00:b0:a2:8c

The guest NIC was still present and remained connected to the expected `virbr0` bridge.

This ruled out a missing or detached virtual NIC configuration.

### 3. Verify Linux Bridge Membership

The bridge configuration was inspected:

    brctl show

Observed result:

    bridge name   bridge id          STP enabled   interfaces
    virbr0        8000.5254007e7a9f  yes           vnet1

The `virbr0` bridge still existed and `vnet1` remained attached to it.

This ruled out bridge removal or accidental interface detachment.

### 4. Inspect TAP Interface State

The host-side TAP interface was inspected directly:

    ip link show vnet1

Observed result:

    vnet1: <BROADCAST,MULTICAST>
    master virbr0
    state DOWN

The expected `UP` and `LOWER_UP` flags were absent.

The same condition was also visible when listing TUN/TAP interfaces:

    ip link show type tun

Observed result:

    vnet1 ... master virbr0 state DOWN

This identified the failed layer in the network path.

---

## Root Cause

The root cause was an administratively disabled host-side TAP interface:

    vnet1

The VM definition remained correct.

The virtual NIC remained connected to `virbr0`.

The Linux bridge remained operational.

However, because `vnet1` was in the `DOWN` state, Layer 2 traffic between the guest virtual NIC and the `virbr0` bridge could not pass.

The effective failure path was:

    ubuntu-guest-01
          |
       virtio NIC
          |
        vnet1
          X
       state DOWN
          |
        virbr0
          |
         NAT
          |
       Internet

The failure was therefore isolated to the host-side TAP interface rather than the guest operating system, libvirt network definition, or Linux bridge configuration.

---

## Recovery

The TAP interface was restored:

    sudo ip link set vnet1 up

The interface state was verified:

    ip link show vnet1

Observed result:

    vnet1: <BROADCAST,MULTICAST,UP,LOWER_UP>
    master virbr0
    state UNKNOWN

The return of `UP` and `LOWER_UP` confirmed that the host-side virtual link was operational again.

---

## Validation

Guest external connectivity was retested:

    ping -c 4 8.8.8.8

Observed result:

    64 bytes from 8.8.8.8: icmp_seq=1 ttl=112
    64 bytes from 8.8.8.8: icmp_seq=2 ttl=112
    64 bytes from 8.8.8.8: icmp_seq=3 ttl=112
    64 bytes from 8.8.8.8: icmp_seq=4 ttl=112

    4 packets transmitted, 4 received, 0% packet loss

Post-recovery interface statistics were collected:

    virsh -c qemu:///system domifstat ubuntu-guest-01 vnet1

Observed result:

    vnet1 rx_bytes   3111802
    vnet1 rx_packets 7175
    vnet1 rx_errors  0
    vnet1 rx_drop    0
    vnet1 tx_bytes   367974
    vnet1 tx_packets 3337
    vnet1 tx_errors  0
    vnet1 tx_drop    0

Compared with the failure-state counters:

    RX packets: 7089 -> 7175
    TX packets: 3315 -> 3337

Traffic counters increased after recovery while errors and drops remained at zero.

This confirmed that network traffic had resumed successfully.

---

## Resolution

INC002 was resolved by restoring the administratively disabled host-side TAP interface.

No VM reboot, guest network reconfiguration, or libvirt network recreation was required.

The final verified state was:

    VM NIC configured:       Healthy
    TAP interface:           UP / LOWER_UP
    Bridge membership:       virbr0
    Guest connectivity:      Healthy
    Packet loss to 8.8.8.8:  0%
    RX/TX errors:            0
    RX/TX drops:             0

---

## Support Engineer Takeaway

The key troubleshooting lesson from this incident was to separate the different layers of KVM networking instead of treating "the VM has no internet" as a single problem.

The investigation followed the network path:

    Guest NIC
        |
        v
    TAP interface
        |
        v
    Linux bridge
        |
        v
    libvirt network / NAT
        |
        v
    Host networking

`virsh domiflist` confirmed that the VM NIC configuration still existed.

`brctl show` confirmed that the TAP interface remained attached to the correct bridge.

`virsh domifstat` showed historical traffic with no RX/TX errors or drops.

`ip link show vnet1` identified the actual failure by showing that the TAP interface was administratively DOWN.

Recovery was performed only after isolating the failed layer.

The incident demonstrated that guest connectivity can fail even when the VM, virtual NIC configuration, bridge membership, and libvirt network remain intact.

For KVM networking incidents, the state of the host-side TAP interface should therefore be checked explicitly rather than assuming the problem exists inside the guest.
