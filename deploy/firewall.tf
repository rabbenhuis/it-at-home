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
  firewall_mgmt_sources = [
    module.cluster.vlans[120].subnet,
    module.cluster.vlans[122].subnet,
  ]

  firewall_mgmt_base = [
    { type = "in", action = "ACCEPT", proto = "tcp", dport = "22",
    source = join(",", local.firewall_mgmt_sources), comment = "SSH (mgmt)" },
    { type = "in", action = "ACCEPT", proto = "icmp", comment = "ICMP (mgmt)" },
  ]

  # AdGuard Home servers: the only clients allowed to query the unbound resolver.
  adguard_dns_servers = ["192.168.90.40", "192.168.90.42"]

  firewall_rules = {
    adguard = [
      # Environment-wide DNS server: 53 open to all VLANs.
      { type = "in", action = "ACCEPT", proto = "udp", dport = "53", comment = "DNS" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "53", comment = "DNS over TCP" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "3000",
      source = join(",", local.firewall_mgmt_sources), comment = "Admin UI (mgmt)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    unbound = [
      # Recursive resolver + DNS views: only the AdGuard servers may query it.
      # Base listener on 53 plus the per-view instances on 5353-5357.
      { type  = "in", action = "ACCEPT", proto = "udp",
        dport = "53,5353,5354,5355,5356,5357",
      source = join(",", local.adguard_dns_servers), comment = "DNS + views (AdGuard)" },
      { type  = "in", action = "ACCEPT", proto = "tcp",
        dport = "53,5353,5354,5355,5356,5357",
      source = join(",", local.adguard_dns_servers), comment = "DNS + views over TCP (AdGuard)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    # haos: add when a Home Assistant host is deployed (e.g. tcp 80/443/8123 from mgmt).
  }
}