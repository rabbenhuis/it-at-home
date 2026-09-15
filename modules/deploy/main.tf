terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }
  }
}

resource "proxmox_virtual_environment_container" "instance" {
  count = var.type == "lxc" ? 1 : 0

  description   = var.description
  node_name     = var.node_name
  vm_id         = var.vmid
  unprivileged  = var.unprivileged
  started       = true
  start_on_boot = var.on_boot

  clone {
    vm_id = var.template_vmid
  }

  dynamic "startup" {
    for_each = var.startup != null ? [1] : []
    content {
      order      = tostring(var.startup.order)
      up_delay   = var.startup.up_delay != null ? tostring(var.startup.up_delay) : null
      down_delay = var.startup.down_delay != null ? tostring(var.startup.down_delay) : null
    }
  }

  # Blank resource values (0) inherit the corresponding template setting.
  dynamic "cpu" {
    for_each = var.cores > 0 ? [1] : []
    content {
      architecture = var.architecture
      cores        = var.cores
    }
  }

  dynamic "memory" {
    for_each = var.memory > 0 ? [1] : []
    content {
      dedicated = var.memory
      swap      = var.swap
    }
  }

  # Features inherit from the template unless explicitly set in the map.
  dynamic "features" {
    for_each = (var.nesting != null || var.fuse != null || var.keyctl != null) ? [1] : []
    content {
      nesting = var.nesting != null ? var.nesting : false
      fuse    = var.fuse != null ? var.fuse : false
      keyctl  = var.keyctl != null ? var.keyctl : false
    }
  }

  initialization {
    hostname = var.hostname

    dns {
      domain  = var.searchdomain
      servers = var.nameserver
    }

    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }

    # No user_account: PVE's clone API rejects ssh-public-keys (HTTP 400).
    # The ansible/sysadm1n users are baked into the source template.
  }

  network_interface {
    name     = "eth0"
    bridge   = var.bridge
    firewall = var.firewall
    vlan_id  = var.vlan_id
  }

  dynamic "disk" {
    for_each = var.disk_size > 0 ? [1] : []
    content {
      datastore_id = var.disk_datastore
      size         = var.disk_size
    }
  }
}

resource "proxmox_virtual_environment_vm" "instance" {
  count = var.type == "vm" ? 1 : 0

  description = var.description
  name        = var.hostname
  node_name   = var.node_name
  vm_id       = var.vmid
  started     = true
  on_boot     = var.on_boot

  stop_on_destroy = true

  clone {
    vm_id = var.template_vmid
  }

  agent {
    enabled = true
  }

  dynamic "startup" {
    for_each = var.startup != null ? [1] : []
    content {
      order      = tostring(var.startup.order)
      up_delay   = var.startup.up_delay != null ? tostring(var.startup.up_delay) : null
      down_delay = var.startup.down_delay != null ? tostring(var.startup.down_delay) : null
    }
  }

  # Blank resource values (0) inherit the corresponding template setting.
  # Disk is always inherited from the template (overriding disks on a clone
  # requires restating every disk attribute - provider gotcha).
  dynamic "cpu" {
    for_each = var.cores > 0 ? [1] : []
    content {
      cores = var.cores
    }
  }

  dynamic "memory" {
    for_each = var.memory > 0 ? [1] : []
    content {
      dedicated = var.memory
    }
  }

  network_device {
    bridge   = var.bridge
    firewall = var.firewall
    vlan_id  = var.vlan_id
  }

  initialization {
    ip_config {
      ipv4 {
        address = var.ip
        gateway = var.gateway
      }
    }

    dns {
      servers = var.nameserver
      domain  = var.searchdomain
    }

    # debian is the cloud-init user baked into the VM template; the key is
    # injected at clone time so ansible can connect as this user (become root).
    user_account {
      username = "debian"
      keys     = var.ssh_keys
    }
  }
}