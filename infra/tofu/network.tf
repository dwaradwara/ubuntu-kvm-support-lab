resource "libvirt_network" "p4_support" {
  name      = "p4-support-net"
  autostart = true

  # No forward block:
  # this is an isolated internal Phase 4 network.

  ips = [
    {
      address = "192.168.140.1"
      netmask = "255.255.255.0"
    }
  ]
}
