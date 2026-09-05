# INC003 — Custom Isolated KVM Network Configuration

| Field | Details |
|---|---|
| Incident ID | INC003 |
| Date | 2026-09-03 |
| Severity | Medium |
| Status | Completed |
| Environment | Ubuntu 24.04.4 LTS KVM guest |
| Guest Hostname | lab-guest-01 |
| Hypervisor | KVM/QEMU with libvirt |
| Existing Network | default |
| Existing Bridge | virbr0 |
| Isolated Network | isolated |
| Isolated Bridge | virbr1 |
| Existing TAP | vnet1 |
| Isolated TAP | vnet2 |
| Existing Guest NIC | enp1s0 |
| Isolated Guest NIC | enp7s0 |

## Scenario

A custom isolated libvirt network was created to demonstrate separation between a VM's normal NAT-connected interface and an additional interface connected to a private virtual network.

The existing guest networking remained intact while a second virtual NIC was attached to a new isolated libvirt network.

The objective was to verify:

- creation of a custom libvirt network
- creation of a separate Linux bridge
- attachment of an additional VM interface
- independent routing through the second NIC
- successful communication across the isolated bridge
- absence of Internet connectivity when traffic was explicitly sourced from the isolated NIC
- preservation of the original NAT-based Internet connection

I scoped INC003 to validate an `isolated` libvirt network by attaching a second virtual interface to the existing guest while preserving its original NAT-connected interface.

---

## Existing Network Architecture

Before the isolated network was created, the VM used the libvirt `default` NAT network.

The existing path was:

    ubuntu-guest-01
          |
        enp1s0
          |
        vnet1
          |
        virbr0
          |
    libvirt default
          |
         NAT
          |
       Internet

The existing interface configuration was:

    Guest interface: enp1s0
    Guest IPv4:      192.168.122.170/24
    Host TAP:        vnet1
    Bridge:          virbr0
    Network:         default

This network remained available throughout INC003.

---

## Isolated Network Definition

A new libvirt network definition was created:

    nano /tmp/isolated-net.xml

The XML configuration was:

    <network>
      <name>isolated</name>
      <bridge name='virbr1'/>
    </network>

The configuration intentionally contained no forwarding mode.

The network was defined with:

    virsh -c qemu:///system net-define /tmp/isolated-net.xml

Observed result:

    Network isolated defined from /tmp/isolated-net.xml

---

## Network Activation

The network was started:

    virsh -c qemu:///system net-start isolated

Observed result:

    Network isolated started

Autostart was enabled:

    virsh -c qemu:///system net-autostart isolated

Observed result:

    Network isolated marked as autostarted

The network state was then verified:

    virsh -c qemu:///system net-list --all

Observed result:

    Name       State    Autostart   Persistent
    -------------------------------------------
    default    active   yes         yes
    isolated   active   yes         yes

This confirmed that the new libvirt network was:

    Active:      yes
    Autostart:   yes
    Persistent:  yes

I defined the isolated network, started it, enabled autostart, and verified its persistent state before attaching the additional VM interface.

---

## Bridge Verification

The host bridge configuration was inspected:

    brctl show

Before attaching a VM interface, the result showed:

    bridge name   bridge id          STP enabled   interfaces
    virbr0        8000.5254007e7a9f  yes           vnet1
    virbr1        8000.525400f80fd2  yes

This confirmed that libvirt created a separate bridge named:

    virbr1

The existing NAT bridge `virbr0` remained unchanged.

---

## Attach Additional VM Interface

A second virtual network interface was attached to `ubuntu-guest-01`:

    virsh -c qemu:///system attach-interface ubuntu-guest-01 \
      --type network \
      --source isolated \
      --model virtio \
      --persistent

Observed result:

    Interface attached successfully

The VM interface configuration was verified:

    virsh -c qemu:///system domiflist ubuntu-guest-01

Observed result:

    Interface   Type      Source     Model    MAC
    ---------------------------------------------------------
    vnet1       bridge    virbr0     virtio   52:54:00:b0:a2:8c
    vnet2       network   isolated   virtio   52:54:00:94:30:ba

This showed two independent virtual interfaces:

    vnet1 -> virbr0 / default network
    vnet2 -> isolated / virbr1

---

## Bridge Membership After Attachment

The bridge configuration was checked again:

    brctl show

Observed result:

    bridge name   bridge id          STP enabled   interfaces
    virbr0        8000.5254007e7a9f  yes           vnet1
    virbr1        8000.525400f80fd2  yes           vnet2

This confirmed that the newly created TAP interface `vnet2` was connected to `virbr1`.

The original `vnet1` interface remained connected to `virbr0`.

---

## Guest Interface Detection

Inside the Ubuntu guest, interfaces were inspected:

    ip -br link

Observed result before activation:

    lo       UNKNOWN
    enp1s0   UP       52:54:00:b0:a2:8c
    enp7s0   DOWN     52:54:00:94:30:ba

The MAC address of `enp7s0` matched the MAC address of `vnet2` shown by `virsh domiflist`.

This established the mapping:

    Guest enp7s0
          |
        vnet2
          |
        virbr1
          |
      isolated

---

## Activate Isolated Guest Interface

The second guest interface was brought up:

    sudo ip link set enp7s0 up

The state was verified:

    ip -br link

Observed result:

    enp7s0   UP   52:54:00:94:30:ba   <BROADCAST,MULTICAST,UP,LOWER_UP>

The interface was therefore operational at Layer 2.

---

## Guest Addressing

The guest interfaces were inspected:

    ip -br addr

The original NAT-connected NIC had:

    enp1s0   UP   192.168.122.170/24

The isolated interface initially had no IPv4 address.

A temporary IPv4 address was assigned for validation:

    sudo ip addr add 10.10.10.10/24 dev enp7s0

Verification:

    ip -br addr

Observed result:

    enp1s0   UP   192.168.122.170/24
    enp7s0   UP   10.10.10.10/24

The `10.10.10.10/24` address was added only for the current validation session.

It was not made persistent through Netplan.

---

## Host-Side Isolated Address

A temporary IPv4 address was assigned to `virbr1` on the host:

    sudo ip addr add 10.10.10.1/24 dev virbr1

The bridge address was verified:

    ip -br addr show virbr1

Observed result:

    virbr1   UP   10.10.10.1/24

This provided an endpoint on the isolated segment for connectivity testing.

This address was also temporary and was not added to the persistent libvirt XML configuration.

---

## Isolated Network Connectivity Test

From the guest, traffic was explicitly forced through `enp7s0`:

    ping -I enp7s0 -c 4 10.10.10.1

Observed result:

    64 bytes from 10.10.10.1: icmp_seq=1 ttl=64
    64 bytes from 10.10.10.1: icmp_seq=2 ttl=64
    64 bytes from 10.10.10.1: icmp_seq=3 ttl=64
    64 bytes from 10.10.10.1: icmp_seq=4 ttl=64

    4 packets transmitted, 4 received, 0% packet loss

This validated the path:

    ubuntu-guest-01
        enp7s0
        10.10.10.10
            |
            v
          vnet2
            |
            v
          virbr1
            |
            v
        10.10.10.1
          host

Traffic successfully passed through the isolated virtual network.

---

## Routing Verification

The guest routing table was inspected:

    ip route

Observed result:

    default via 192.168.122.1 dev enp1s0 proto dhcp src 192.168.122.170 metric 100
    10.10.10.0/24 dev enp7s0 proto kernel scope link src 10.10.10.10
    192.168.122.0/24 dev enp1s0 proto kernel scope link src 192.168.122.170 metric 100
    192.168.122.1 dev enp1s0 proto dhcp scope link src 192.168.122.170 metric 100

This showed two separate routes:

    Internet/default traffic
        -> enp1s0
        -> 192.168.122.1
        -> virbr0
        -> NAT

    10.10.10.0/24 traffic
        -> enp7s0
        -> vnet2
        -> virbr1

The isolated interface did not replace or modify the default route.

---

## Original Internet Connectivity Validation

Internet connectivity through the existing NAT interface was tested:

    ping -c 4 8.8.8.8

Observed result:

    4 packets transmitted, 4 received, 0% packet loss

This confirmed that attaching the isolated network did not disrupt the VM's original Internet connectivity.

---

## Isolation Validation

Internet traffic was then explicitly forced through the isolated NIC:

    ping -I enp7s0 -c 4 8.8.8.8

Observed result:

    PING 8.8.8.8 (8.8.8.8) from 10.10.10.10 enp7s0

    4 packets transmitted, 0 received, 100% packet loss

This was the expected result.

The isolated interface could communicate with the local isolated segment but did not provide an Internet path.

The validation showed:

    enp1s0 -> Internet              PASS
    enp7s0 -> 10.10.10.1           PASS
    enp7s0 -> Internet              BLOCKED / EXPECTED

---

## Final Network Architecture

The completed topology was:

                     ubuntu-guest-01
                    /               \
                   /                 \
              enp1s0                enp7s0
         192.168.122.170          10.10.10.10
                 |                     |
               vnet1                 vnet2
                 |                     |
               virbr0                virbr1
                 |                     |
          default network         isolated network
                 |
                NAT
                 |
              Internet

The two networks served different purposes and remained independently routable.

---

## Result

INC003 successfully demonstrated creation and validation of a custom isolated libvirt network.

Verified state:

    isolated network defined:       yes
    isolated network active:        yes
    isolated network persistent:    yes
    isolated network autostart:     yes
    virbr1 created:                 yes
    vnet2 attached to virbr1:       yes
    guest enp7s0 detected:          yes
    guest enp7s0 operational:       yes
    isolated local connectivity:    yes
    isolated Internet access:       no
    original NAT connectivity:      yes

---

## Persistence Notes

The libvirt `isolated` network itself is persistent and configured for autostart.

The additional VM interface was attached using:

    --persistent

However, the test addresses:

    Guest enp7s0: 10.10.10.10/24
    Host virbr1:   10.10.10.1/24

were assigned using `ip addr add`.

Those IPv4 addresses are temporary runtime configuration.

A reboot or network restart can remove them.

A production implementation would require persistent guest-side network configuration and, if host addressing is required, persistent configuration in the libvirt network definition or another appropriate network-management layer.

---

## Scope Limitation

INC003 was implemented using a second virtual interface on `ubuntu-guest-01`; a second VM was not attached to the `isolated` network.

I therefore treated the scope as validation of the isolated libvirt network, bridge, TAP interface, routing behavior, and separation from the guest's existing NAT-connected interface.

This incident does not claim that VM-to-VM communication was tested.

What was directly validated was:

    guest -> isolated TAP -> isolated bridge -> host endpoint

A full two-VM isolation test would require attaching another VM to the same `isolated` network, assigning it an address in the same subnet, and verifying communication between the two guests.

---

## Support Engineer Takeaway

The important diagnostic distinction is that a VM can participate in multiple virtual networks simultaneously.

In this lab:

    enp1s0 / vnet1 / virbr0

provided the normal NAT-connected network, while:

    enp7s0 / vnet2 / virbr1

provided a separate isolated network path.

`virsh net-list --all` verified the libvirt network lifecycle.

`virsh domiflist` mapped VM interfaces to their libvirt networks.

`brctl show` verified TAP-to-bridge membership.

`ip -br link` and `ip -br addr` verified guest interface state and addressing.

`ip route` verified that the original default route remained unchanged.

Interface-specific ping tests proved which network path traffic was actually using.

The key lesson is that successful virtual NIC attachment alone does not prove network functionality. Interface state, addressing, routing, bridge membership, and end-to-end connectivity must all be validated separately.
