# Role-based PVE firewall rules. A host gets a rule set only if its `role` is
# registered here; the set is the COMPLETE inbound rule set for that guest
# (the .fw file is wholesale-replaced). Management base rules (SSH/ICMP from
# the workstation VLANs) are prepended automatically in deploy/main.tf.
#
# Rule fields: type (in/out/forward), action (ACCEPT/DROP/REJECT), proto,
# dport/sport, source/dest (IP/network, comma-separated list allowed), iface,
# log, comment. `source`/`dest` can reference an alias or '+ipsetname'.
locals {
  # Workstation (WSL on Windows) is on VLAN 120 wired, VLAN 122 Wi-Fi.
  # These VLANs render into the cluster-level ipset 'mgmt-sources'
  # (proxmox_virtual_environment_firewall_ipset.mgmt_sources) and are
  # referenced from the base SSH rule and role admin-UI rules.
  firewall_mgmt_vlans   = [120, 122]
  firewall_mgmt_sources = [for id in local.firewall_mgmt_vlans : module.cluster.vlans[id]]

  firewall_mgmt_base = [
    { type = "in", action = "ACCEPT", proto = "tcp", dport = "22",
    source = "+mgmt-sources", comment = "SSH (mgmt)" },
    { type = "in", action = "ACCEPT", proto = "icmp", comment = "ICMP (mgmt)" },
  ]

  # AdGuard Home servers: the only clients allowed to query the unbound
  # resolver. Rendered into the cluster-level ipset 'adguard-servers' and used
  # as the source of the unbound rules.
  adguard_dns_servers = [
    { ip = "192.168.90.40", name = "adguard-pri01" },
    { ip = "192.168.90.42", name = "adguard-sec01" },
  ]

  # VLANs that may query the AdGuard DNS servers (all AdGuard-served VLANs;
  # guest 142 uses the router's DNS). Rendered into a cluster-level ipset
  # (proxmox_virtual_environment_firewall_ipset.adguard_dns_sources) and used
  # as the source of the adguard port-53 rules, so DNS is restricted per node
  # as well as on the MikroTik.
  adguard_dns_vlans   = [37, 70, 75, 80, 90, 95, 100, 115, 120, 122, 132, 150, 152, 160]
  adguard_dns_sources = [for id in local.adguard_dns_vlans : module.cluster.vlans[id]]

  firewall_rules = {
    adguard = [
      # Environment-wide DNS server: 53 open to the AdGuard-served VLANs only.
      { type = "in", action = "ACCEPT", proto = "udp", dport = "53",
      source = "+adguard-dns-sources", comment = "DNS (AdGuard VLANs)" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "53",
      source = "+adguard-dns-sources", comment = "DNS over TCP (AdGuard VLANs)" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "3000",
      source = "+mgmt-sources", comment = "Admin UI (mgmt)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    unbound = [
      # Recursive resolver + DNS views: only the AdGuard servers may query it.
      # Base listener on 53 plus the per-view instances on 5353-5357.
      { type  = "in", action = "ACCEPT", proto = "udp",
        dport = "53,5353,5354,5355,5356,5357",
      source = "+adguard-servers", comment = "DNS + views (AdGuard)" },
      { type  = "in", action = "ACCEPT", proto = "tcp",
        dport = "53,5353,5354,5355,5356,5357",
      source = "+adguard-servers", comment = "DNS + views over TCP (AdGuard)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    # haos: add when a Home Assistant host is deployed (e.g. tcp 80/443/8123 from mgmt).
  }
}