# Deployment map - one entry per host. This is the single source of truth for
# deployed containers/VMs; edit it, then run scripts/deploy-hosts.sh.
#
# Fields:
#   type          "lxc" or "vm"
#   target        node: "pve1" (amd64) or "pve2" (arm64)
#   vlan_id       VLAN ID; gateway/nameserver/search-domain resolve from the
#                 vlans registry in modules/cluster-data
#   template_vmid template to clone: 9000 native / 9010 podman / 9020 docker / 9200 vm
#   vmid          unique VMID (keep clear of the 9000-9200 template range)
#   ip            static IPv4 in CIDR, on the VLAN's subnet
#   cores         CPU cores (omit = inherit template)
#   memory        RAM in MB (omit = inherit template)
#   disk_size     rootfs/disk in GB, LXC only (omit = inherit; VM disk is always inherited)
#   on_boot       start at host boot (default true)
#   startup       startup/shutdown order & delays: { order, up_delay?, down_delay? }
#                 (omit = left unset)
#   unprivileged  LXC only (default true)
#   nesting/fuse/keyctl  LXC features (omit = inherit template)
#   role          service role to apply post-deploy, mapped to an ansible playbook
#                 in deploy/roles.tf (e.g. "adguard", "unbound", "haos", "harden");
#                 omit = skip
#   backup        backup tier from deploy/backup.tf ("tier-0".."tier-3"); hosts in
#                 the same tier share one backup job. omit = not backed up
#   description   free-form note shown in the Proxmox container/VM notes field
#                 (omit = "Managed by Terraform (deployed from template vmid N)")
locals {
  deployments = {
    adguard-pri01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 201
      cores         = 2
      memory        = 512
      disk_size     = 8
      ip            = "192.168.90.40/24"
      on_boot       = true
      startup       = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged  = true
      role          = "adguard"
      backup        = "tier-0"
      description   = "Primary AdGuard Home DNS blocker (Managed by Terraform)"
    }
    unbound-pri01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 202
      cores         = 1
      memory        = 1024
      disk_size     = 8
      ip            = "192.168.90.41/24"
      on_boot       = true
      startup       = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged  = true
      role          = "unbound"
      backup        = "tier-0"
      description   = "Primary recursive resolver (Managed by Terraform)"
    }
    adguard-sec01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 205
      cores         = 2
      memory        = 512
      disk_size     = 8
      ip            = "192.168.90.42/24"
      on_boot       = true
      startup       = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged  = true
      nesting       = false
      keyctl        = false
      fuse          = false
      role          = "adguard"
      backup        = "tier-0"
      description   = "Secondary AdGuard Home DNS blocker (Managed by Terraform)"
    }
    unbound-sec01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 206
      cores         = 1
      memory        = 1024
      disk_size     = 8
      ip            = "192.168.90.43/24"
      on_boot       = true
      startup       = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged  = true
      nesting       = false
      keyctl        = false
      fuse          = false
      role          = "unbound"
      backup        = "tier-0"
      description   = "Secondary recursive resolver (Managed by Terraform)"
    }
    # web1 = {
    #   type          = "lxc"
    #   target        = "pve1"
    #   vlan_id       = 70
    #   template_vmid = 9010
    #   vmid          = 101
    #   cores         = 2
    #   memory        = 1024
    #   disk_size     = 16
    #   ip            = "192.168.70.11/24"
    #   on_boot       = true
    #   startup       = { order = 10, up_delay = 30, down_delay = 30 }
    #   unprivileged  = true
    #   nesting       = true
    #   role          = "adguard"
    #   description   = "AdGuard Home DNS blocker"
    # }
    #
    # db1 = {
    #   type          = "lxc"
    #   target        = "pve2"
    #   vlan_id       = 70
    #   template_vmid = 9000
    #   vmid          = 102
    #   cores         = 4
    #   memory        = 4096
    #   disk_size     = 32
    #   ip            = "192.168.70.21/24"
    # }
    #
    # app1 = {
    #   type          = "vm"
    #   target        = "pve1"
    #   vlan_id       = 70
    #   template_vmid = 9200
    #   vmid          = 110
    #   cores         = 2
    #   memory        = 4096
    #   ip            = "192.168.70.31/24"
    #   role          = "unbound"
    # }
  }
}
