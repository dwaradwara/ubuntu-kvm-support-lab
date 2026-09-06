locals {
  web_mgmt_mac    = "52:54:00:14:00:11"
  web_support_mac = "52:54:00:14:00:10"
  web_support_ip  = "192.168.140.10"

  ssh_public_key = trimspace(
    file(pathexpand("~/.ssh/canonical-lab.pub"))
  )
}

resource "libvirt_volume" "web_disk" {
  name       = "p4-web-01.qcow2"
  pool       = "lab-pool"
  capacity   = 21474836480
  allocation = 0

  target = {
    format = {
      type = "qcow2"
    }
  }

  backing_store = {
    path = libvirt_volume.ubuntu_base.path

    format = {
      type = "qcow2"
    }
  }
}

resource "libvirt_cloudinit_disk" "web_init" {
  name = "p4-web-01-init"

  user_data = templatefile(
    "${path.module}/../cloud-init/p4-web-user-data.yaml.tftpl",
    {
      ssh_public_key = local.ssh_public_key
      db_password    = random_password.phase4_db.result
    }
  )

  meta_data = yamlencode({
    instance-id    = "p4-web-01"
    local-hostname = "p4-web-01"
  })

  network_config = templatefile(
    "${path.module}/../cloud-init/p4-web-network.yaml.tftpl",
    {
      mgmt_mac    = local.web_mgmt_mac
      support_mac = local.web_support_mac
      support_ip  = local.web_support_ip
    }
  )
}

resource "libvirt_volume" "web_cloudinit" {
  name = "p4-web-01-cloudinit.iso"
  pool = "lab-pool"

  create = {
    content = {
      url = libvirt_cloudinit_disk.web_init.path
    }
  }
}

resource "libvirt_domain" "web" {
  name        = "p4-web-01"
  memory      = 2048
  memory_unit = "MiB"
  vcpu        = 2
  type        = "kvm"

  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
  }

  features = {
    acpi = true
    apic = {}
  }

  devices = {
    disks = [
      {
        source = {
          volume = {
            pool   = libvirt_volume.web_disk.pool
            volume = libvirt_volume.web_disk.name
          }
        }

        target = {
          bus = "virtio"
          dev = "vda"
        }

        driver = {
          type = "qcow2"
        }
      },
      {
        device = "cdrom"

        source = {
          volume = {
            pool   = libvirt_volume.web_cloudinit.pool
            volume = libvirt_volume.web_cloudinit.name
          }
        }

        target = {
          bus = "sata"
          dev = "sda"
        }
      }
    ]

    interfaces = [
      {
        model = {
          type = "virtio"
        }

        mac = {
          address = local.web_mgmt_mac
        }

        source = {
          network = {
            network = "default"
          }
        }
      },
      {
        model = {
          type = "virtio"
        }

        mac = {
          address = local.web_support_mac
        }

        source = {
          network = {
            network = libvirt_network.p4_support.name
          }
        }
      }
    ]

    serials = [
      {
        type = "pty"
        target = {
          type = "isa-serial"
          port = 0
        }
      }
    ]

    consoles = [
      {
        type = "pty"
        target = {
          type = "serial"
          port = 0
        }
      }
    ]
    rngs = [
      {
        model = "virtio"
        backend = {
          random = "/dev/urandom"
        }
      }
    ]

    graphics = [
      {
        vnc = {
          auto_port = true
          listen    = "127.0.0.1"
        }
      }
    ]
  }

  running = true
}
