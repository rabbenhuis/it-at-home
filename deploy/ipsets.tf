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