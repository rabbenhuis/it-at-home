terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_vm" "build" {
  description = "Managed by Terraform (template build vm v${var.template_version})"
  name        = var.hostname
  node_name   = var.node_name
  vm_id       = var.vmid
  started     = true

  # Ephemeral build instance: don't auto-start after a node reboot.
  on_boot = false

  stop_on_destroy = true

  agent {
    enabled = true
  }

  cpu {
    # cpu.architecture can only be set by root; PVE defaults to the host arch
    # (x86_64 on amd64, aarch64 on arm64), which matches the cloud image.
    cores = var.cores
  }

  memory {
    dedicated = var.memory
  }

  disk {
    datastore_id = var.disk_datastore
    interface    = "scsi0"
    size         = var.disk_size
    import_from  = var.cloud_image_file_id
  }

  network_device {
    bridge   = var.bridge
    vlan_id  = var.vlan_id
    firewall = var.firewall
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = [var.nameserver]
      domain  = var.searchdomain
    }

    # debian is the default user of the Debian cloud image; the key is injected
    # via cloud-init so ansible can connect as this user (become root).
    user_account {
      username = "debian"
      keys     = var.ssh_keys
    }
  }

  operating_system {
    type = var.ostype
  }

  lifecycle {
    ignore_changes = [initialization[0].user_account]
  }
}