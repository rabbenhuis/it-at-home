# Cluster-level PVE firewall IP set (the PVE equivalent of a MikroTik address
# list): the VLANs allowed to query the AdGuard DNS servers. Referenced from
# the adguard role's port-53 rules as source "+adguard-dns-sources".
resource "proxmox_virtual_environment_firewall_ipset" "adguard_dns_sources" {
  provider = proxmox.pve1

  name    = "adguard-dns-sources"
  comment = "VLANs allowed to query the AdGuard DNS servers"

  dynamic "cidr" {
    for_each = local.adguard_dns_sources
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}

# Management VLANs (workstation wired/Wi-Fi) - source for the SSH base rule
# and role admin-UI rules (e.g. AdGuard 3000).
resource "proxmox_virtual_environment_firewall_ipset" "mgmt_sources" {
  provider = proxmox.pve1

  name    = "mgmt-sources"
  comment = "Management VLANs (SSH/admin access to deployed hosts)"

  dynamic "cidr" {
    for_each = local.firewall_mgmt_sources
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}