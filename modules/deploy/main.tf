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
      units        = var.cpuunits > 0 ? var.cpuunits : null
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

  # Link-only extra NICs (eth1..N): no IP, one VLAN each. Used e.g. by an mDNS
  # reflector to receive multicast on several VLANs without addresses.
  dynamic "network_interface" {
    for_each = var.extra_networks
    content {
      name     = "eth${network_interface.key + 1}"
      bridge   = var.bridge
      firewall = network_interface.value.firewall
      vlan_id  = network_interface.value.vlan_id
    }
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
      units = var.cpuunits > 0 ? var.cpuunits : null
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
    # VirtIO multiqueue (matches the vm template).
    queues = 2
  }

  initialization {
    # Cloud-init drive datastore. Required explicitly on clones: the bpg
    # provider defaults it to 'local-lvm', and the deploy clone does not declare
    # a disk block (disks are inherited from the template), so without this the
    # cloud-init drive would be created on non-existent local-lvm.
    datastore_id = var.disk_datastore

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

# Home Assistant OS (HAOS): an appliance image (haos_ova-<ver>.qcow2), NOT a
# clone of the Debian VM template. The image is imported fresh per deploy
# (static nas:import/ reference provisioned manually, like the Debian cloud
# image). HAOS requires UEFI (OVMF/q35), an EFI disk and a scsi0 boot disk; it
# has no cloud-init (the map's `ip` is applied manually via the HAOS console
# after first boot) and is managed by its own UI, so no ansible provisioning.
# qemu-guest-agent is baked into the image (enabled here so the PVE UI shows
# the guest IP/uptime and HAOS exposes host stats).
resource "proxmox_virtual_environment_vm" "haos" {
  count = var.type == "haos" ? 1 : 0

  description = var.description
  name        = var.hostname
  node_name   = var.node_name
  vm_id       = var.vmid
  started     = true
  on_boot     = var.on_boot

  stop_on_destroy = true

  bios    = "ovmf"
  machine = "q35"

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

  dynamic "cpu" {
    for_each = var.cores > 0 ? [1] : []
    content {
      cores = var.cores
      units = var.cpuunits > 0 ? var.cpuunits : null
    }
  }

  dynamic "memory" {
    for_each = var.memory > 0 ? [1] : []
    content {
      dedicated = var.memory
    }
  }

  # EFI disk required by OVMF; type "4m". pre_enrolled_keys must be OFF for
  # HAOS: enrolling the MS keys enables Secure Boot, and HAOS boots an unsigned
  # systemd-boot/kernel, so OVMF rejects the boot entry ("Access Denied ...
  # rejected probably by secure boot"). The Debian VM template keeps keys
  # (Debian ships a signed shim); HAOS does not.
  efi_disk {
    datastore_id      = var.disk_datastore
    type              = "4m"
    pre_enrolled_keys = false
  }

  # scsi0 = the imported HAOS qcow2, grown to the requested size.
  disk {
    datastore_id = var.disk_datastore
    interface    = "scsi0"
    size         = var.disk_size
    import_from  = var.haos_image
  }

  network_device {
    bridge   = var.bridge
    firewall = var.firewall
    vlan_id  = var.vlan_id
    # VirtIO multiqueue (matches the vm template).
    queues = 2
  }

  operating_system {
    type = "l26"
  }
}

# Per-guest PVE firewall options: enables the deny-by-default .fw ruleset.
# The firewall_rules resource only writes the [RULES] section; without
# [OPTIONS] enable: 1 PVE skips guest rule generation and installs an
# ACCEPT-all chain (see PVE::Firewall generate_tap_rules_direction). Only
# created when the host's role provides rules; created/destroyed with the host.
resource "proxmox_virtual_environment_firewall_options" "instance" {
  count = length(var.firewall_rules) > 0 ? 1 : 0

  depends_on = [
    proxmox_virtual_environment_container.instance,
    proxmox_virtual_environment_vm.instance,
    proxmox_virtual_environment_vm.haos,
  ]

  node_name     = var.node_name
  container_id  = var.type == "lxc" ? var.vmid : null
  vm_id         = var.type == "vm" || var.type == "haos" ? var.vmid : null
  enabled       = true
  input_policy  = "DROP"
  output_policy = "ACCEPT"
}

# Per-guest PVE firewall rules (the .fw file is replaced wholesale). Only
# created when the host's role provides rules; created/destroyed with the host.
# Depends on the options resource so [OPTIONS] and [RULES] don't clobber each
# other while writing the same .fw file.
resource "proxmox_virtual_environment_firewall_rules" "instance" {
  count = length(var.firewall_rules) > 0 ? 1 : 0

  depends_on = [
    proxmox_virtual_environment_container.instance,
    proxmox_virtual_environment_vm.instance,
    proxmox_virtual_environment_vm.haos,
    proxmox_virtual_environment_firewall_options.instance,
  ]

  node_name    = var.node_name
  container_id = var.type == "lxc" ? var.vmid : null
  vm_id        = var.type == "vm" || var.type == "haos" ? var.vmid : null

  dynamic "rule" {
    for_each = var.firewall_rules
    content {
      type    = rule.value.type
      action  = rule.value.action
      comment = try(rule.value.comment, null)
      proto   = try(rule.value.proto, null)
      dport   = try(rule.value.dport, null)
      sport   = try(rule.value.sport, null)
      source  = try(rule.value.source, null)
      dest    = try(rule.value.dest, null)
      iface   = try(rule.value.iface, null)
      log     = try(rule.value.log, null)
    }
  }
}