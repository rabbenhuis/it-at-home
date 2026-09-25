# Deployment map - one entry per host. This is the single source of truth for
# deployed containers/VMs; edit it, then run scripts/deploy-hosts.sh.
#
# Fields:
#   type          "lxc", "vm" or "haos" (haos imports the HAOS qcow2 image
#                 fresh: UEFI/OVMF, EFI disk, no cloud-init - not a template clone)
#   target        node: "pve1" (amd64) or "pve2" (arm64)
#   vlan_id       VLAN ID; gateway/nameserver/search-domain resolve from the
#                 vlans registry in modules/cluster-data
#   template_vmid template to clone: 9000 native / 9010 podman / 9020 docker / 9200 vm
#   vmid          unique VMID (keep clear of the 9000-9200 template range)
#   ip            static IPv4 in CIDR, on the VLAN's subnet
#   cores         CPU cores (omit = inherit template)
#   memory        RAM in MB (omit = inherit template)
#   cpuunits      CPU weight for fair-share scheduling (omit = inherit template,
#                 default 1024); raise on latency-sensitive hosts so they keep
#                 responsive under CPU contention (e.g. DNS during VM deploys)
#   disk_size     rootfs/disk in GB, LXC only (omit = inherit; VM disk is always inherited)
#   disk_datastore datastore for the disk: "local-ssd" (node default) or
#                 "local-usbssd" (external USB SSD); omit = node default.
#                 VM clones inherit their disk from the template, so this only
#                 moves the VM's cloud-init drive - pick the datastore when
#                 building the VM template instead. For type "haos" the disk is
#                 created at deploy time (image import), so this DOES matter.
#   extra_networks additional link-only LXC NICs (eth1..N, no IP): each
#                 { vlan_id, firewall? }. Used e.g. by the mDNS reflector to
#                 receive multicast on multiple VLANs without addresses.
#                 "lxc" only; omit = eth0 only.
#   on_boot       start at host boot (default true)
#   startup       startup/shutdown order & delays: { order, up_delay?, down_delay? }
#                 (omit = left unset)
#   unprivileged  LXC only (default true)
#   nesting/fuse/keyctl  LXC features (omit = inherit template)
#   role          service role to apply post-deploy, mapped to an ansible playbook
#                 in deploy/roles.tf (e.g. "adguard", "unbound", "haos", "harden");
#                 omit = skip
#   firewall_role firewall ruleset key in deploy/firewall.tf when it differs from
#                 `role` (e.g. "haos" on haos01, which has no ansible provisioning);
#                 omit = use `role`
#   backup        backup tier from deploy/backup.tf ("tier-0".."tier-3"); hosts in
#                 the same tier share one backup job. omit = not backed up
#   description   free-form note shown in the Proxmox container/VM notes field
#                 (omit = "Managed by Terraform (deployed from template vmid N)")
locals {
  deployments = {
    adguard-pri01 = {
      type           = "lxc"
      target         = "pve1"
      vlan_id        = 90
      template_vmid  = 9000
      vmid           = 201
      cores          = 1
      memory         = 512
      cpuunits       = 4096
      disk_size      = 8
      disk_datastore = "local-usbssd"
      ip             = "192.168.90.40/24"
      on_boot        = true
      startup        = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged   = true
      role           = "adguard"
      backup         = "tier-0"
      description    = "Primary AdGuard Home DNS blocker (Managed by Terraform)"
    }
    unbound-pri01 = {
      type           = "lxc"
      target         = "pve1"
      vlan_id        = 90
      template_vmid  = 9000
      vmid           = 202
      cores          = 1
      memory         = 512
      cpuunits       = 4096
      disk_size      = 8
      disk_datastore = "local-usbssd"
      ip             = "192.168.90.41/24"
      on_boot        = true
      startup        = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged   = true
      role           = "unbound"
      backup         = "tier-0"
      description    = "Primary recursive resolver (Managed by Terraform)"
    }
    adguard-sec01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 205
      cores         = 1
      memory        = 512
      cpuunits      = 4096
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
      memory        = 512
      cpuunits      = 4096
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
    unifi01 = {
      type          = "vm"
      target        = "pve1"
      vlan_id       = 37
      template_vmid = 9200
      vmid          = 100
      cores         = 2
      # TEMP: 3 GB while the Pi workloads are being migrated to pve1; bump back
      # to 4096 once pve2 is up and some workloads move to the Pi.
      memory         = 3072
      disk_datastore = "local-usbssd"
      ip             = "192.168.37.40/24"
      on_boot        = true
      startup        = { order = 30, up_delay = 15, down_delay = 180 }
      role           = "unifi"
      backup         = "tier-1"
      description    = "UniFi OS Server - Network controller for UniFi gear (Managed by Terraform)"
    }
    infra-core01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 204
      cores         = 1
      memory        = 512
      disk_size     = 16
      ip            = "192.168.90.45/24"
      on_boot       = true
      startup       = { order = 20, up_delay = 15, down_delay = 60 }
      unprivileged  = true
      role          = "infra-core"
      description   = "NTP time server + postfix relay (replaces Pi docker relay) (Managed by Terraform)"
    }
    avahi01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 90
      template_vmid = 9000
      vmid          = 203
      cores         = 1
      memory        = 256
      disk_size     = 8
      ip            = "192.168.90.44/24"
      on_boot       = true
      startup       = { order = 25, up_delay = 15, down_delay = 45 }
      role          = "avahi"
      backup        = "tier-3"
      # Link-only NICs (no IP): receive/reflect mDNS on each VLAN. firewall is
      # off on these so the deny-by-default guest firewall can't drop multicast.
      extra_networks = [
        { vlan_id = 100, firewall = false },
        { vlan_id = 120, firewall = false },
        { vlan_id = 122, firewall = false },
        { vlan_id = 132, firewall = false },
        { vlan_id = 150, firewall = false },
        { vlan_id = 152, firewall = false },
      ]
      description = "mDNS reflector (avahi) - bridges service discovery across VLANs (Managed by Terraform)"
    }
    haos01 = {
      type    = "haos"
      target  = "pve1"
      vlan_id = 100
      vmid    = 101
      cores   = 2
      # TEMP: 3 GB while the Pi workloads are being migrated to pve1; bump back
      # to 4096 once pve2 is up and some workloads move to the Pi.
      memory        = 3072
      disk_size     = 32
      ip            = "192.168.100.40/24"
      on_boot       = true
      startup       = { order = 40, up_delay = 10, down_delay = 180 }
      firewall_role = "haos"
      backup        = "tier-2"
      description   = "Home Assistant OS - smart home hub (Managed by Terraform)"
    }
    mosquitto01 = {
      type          = "lxc"
      target        = "pve1"
      vlan_id       = 150
      template_vmid = 9000
      vmid          = 401
      cores         = 1
      memory        = 512
      disk_size     = 8
      ip            = "192.168.150.40/24"
      on_boot       = true
      startup       = { order = 30, up_delay = 15, down_delay = 60 }
      unprivileged  = true
      role          = "mqtt"
      backup        = "tier-2"
      description   = "MQTT broker (mosquitto) - IoT messaging (Managed by Terraform)"
    }
  }
}
