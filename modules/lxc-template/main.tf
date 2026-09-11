terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_container" "build" {
  description  = "Managed by Terraform (template build ${var.role} v${var.template_version})"
  node_name    = var.node_name
  vm_id        = var.vmid
  unprivileged = var.unprivileged
  started      = true

  cpu {
    cores = var.cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  features {
    fuse    = var.fuse
    keyctl  = var.keyctl
    nesting = var.nesting
  }

  initialization {
    hostname = var.hostname

    dns {
      domain  = var.searchdomain
      servers = [var.nameserver]
    }

    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }

    user_account {
      keys = var.ssh_keys
    }
  }

  network_interface {
    name     = "eth0"
    bridge   = var.bridge
    firewall = var.firewall
    vlan_id  = var.vlan_id
  }

  disk {
    datastore_id = var.disk_datastore
    size         = var.disk_size
  }

  dynamic "operating_system" {
    for_each = var.base_template_file != "" ? [1] : []
    content {
      template_file_id = var.base_template_file
      type             = var.ostype
    }
  }

  dynamic "clone" {
    for_each = var.base_clone_id > 0 ? [1] : []
    content {
      vm_id = var.base_clone_id
    }
  }
}