resource "proxmox_virtual_environment_vm" "this" {
  # 1. Core Identifiers
  name      = var.name
  node_name = var.node_name

  # Enable the QEMU guest agent so Proxmox (and OpenTofu) cane see the VM's dynamic IP Address
  agent {
    enabled = true
  }

  # 2. Clone Settings
  # full = true ensures the VM is independent of the template (not a linked clone)
  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  # 3. Hardware specs
  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory_mb
  }

  disk {
    datastore_id = "local-lvm" # this is usually the default storage on Proxmox
    interface    = "virtio0"
    size         = var.disk_size
  }

  network_device {
    bridge = "vmbr0"
  }

  # 4. Cloud-init (initialization)
  initialization {
    ip_config {
      ipv4 {
        address = var.ipv4_address
        gateway = var.ipv4_gateway
      }
    }
    user_account {
      username = var.username
      keys     = var.ssh_public_keys
    }
  }
}
