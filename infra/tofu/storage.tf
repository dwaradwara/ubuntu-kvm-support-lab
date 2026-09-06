resource "libvirt_volume" "ubuntu_base" {
  name = "p4-ubuntu-base.qcow2"
  pool = "lab-pool"

  target = {
    format = {
      type = "qcow2"
    }
  }

  create = {
    content = {
      url = "https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
    }
  }
}
