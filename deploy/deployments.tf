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
#   unprivileged  LXC only (default true)
#   nesting/fuse/keyctl  LXC features (omit = inherit template)
#   playbook      ansible playbook to run post-deploy (e.g. "harden.yml"); omit = skip
locals {
  deployments = {
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
    #   unprivileged  = true
    #   nesting       = true
    #   playbook      = "harden.yml"
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
    #   playbook      = "vm.yml"
    # }
  }
}