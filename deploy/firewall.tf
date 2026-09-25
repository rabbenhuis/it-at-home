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
  # as well as on the MikroTik. WireGuard clients are included so roaming
  # devices can resolve internal names.
  adguard_dns_vlans = [37, 70, 75, 80, 90, 95, 100, 115, 120, 122, 132, 150, 152, 160]
  adguard_dns_sources = concat(
    [for id in local.adguard_dns_vlans : module.cluster.vlans[id]],
    local.firewall_wg_client_cidrs,
  )

  # VLANs hosting UniFi managed devices (switches/APs), which must reach the
  # UniFi OS Server for inform/adoption/STUN/discovery. Rendered into the
  # cluster-level ipset 'unifi-device-sources'. Add any VLAN that carries UniFi
  # gear here (device VLANs only - client VLANs never talk to the controller).
  unifi_device_vlans   = [37]
  unifi_device_sources = [for id in local.unifi_device_vlans : module.cluster.vlans[id]]

  # Human-facing Home Assistant UI (web dashboard). Management VLANs only -
  # IoT devices don't get the dashboard. Rendered into 'haos-ui-sources'.
  firewall_haos_ui_vlans   = [120, 122, 132]
  firewall_haos_ui_sources = [for id in local.firewall_haos_ui_vlans : module.cluster.vlans[id]]

  # IoT VLANs that HAOS integrates with (MQTT broker, Matter server, zigbee2mqtt,
  # Chromecast/Nest on 150/152). Inbound mDNS/SSDP/Matter/cast replies plus MQTT.
  # Rendered into 'haos-iot-sources'.
  firewall_haos_iot_vlans   = [150, 152]
  firewall_haos_iot_sources = [for id in local.firewall_haos_iot_vlans : module.cluster.vlans[id]]

  # WireGuard overlay (interface wg-home, 172.18.10.0/24). All peers may reach
  # the HAOS UI (presence/proximity); wg-darth-sidious (172.18.10.26, private
  # phone) and wg-laptop (172.18.10.37) may also reach the other admin services
  # (UniFi controller, ...). Rendered into the cluster-level ipsets
  # 'wg-sources' / 'wg-admin'.
  firewall_wg_client_cidrs = [
    { subnet = "172.18.10.0/24", name = "WireGuard clients (wg-home)" },
  ]
  firewall_wg_admin_cidrs = [
    { subnet = "172.18.10.26", name = "wg-darth-sidious (private phone)" },
    { subnet = "172.18.10.37", name = "wg-laptop" },
  ]

  # Server VLANs allowed to sync NTP from the infra-core time server
  # (192.168.90.45). Client VLANs excluded. Rendered into 'ntp-sources'.
  firewall_ntp_vlans   = [37, 70, 75, 80, 90, 95, 100, 115, 150]
  firewall_ntp_sources = [for id in local.firewall_ntp_vlans : module.cluster.vlans[id]]

  # Known MQTT broker clients (mosquitto01): Home Assistant (Pi container until
  # HA migrates, then haos01) and the future zigbee2mqtt container. Rendered
  # into 'mqtt-client-sources'. Keeps port 1883 closed to unauthenticated IoT
  # devices on the IoT VLANs.
  firewall_mqtt_client_cidrs = [
    { ip = "192.168.100.70", name = "Pi home-assistant (pre-migration)" },
    { ip = "192.168.100.75", name = "mqtt-explorer (Pi)" },
    { ip = "192.168.100.40", name = "haos01" },
    { ip = "192.168.150.42", name = "zigbee01 (zigbee2mqtt)" },
  ]

  # Internal hosts allowed to relay mail through the infra-core postfix relay.
  # Every VLAN subnet except the guest WLAN (142 must not relay) plus the
  # WireGuard overlay. Rendered into 'mail-relay-sources'.
  firewall_mail_relay_sources = concat(
    [for id, v in module.cluster.vlans : v if id != 142],
    local.firewall_wg_client_cidrs,
  )

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
    unifi = [
      # UniFi OS Server: admin UI on 11443 (web console) from mgmt VLANs.
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "11443",
      source = "+mgmt-sources", comment = "Admin UI (mgmt)" },
      # UniFi OS Server: admin UI from the private phone over WireGuard.
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "11443",
      source = "+wg-admin", comment = "Admin UI (WireGuard phone)" },
      # Device adoption/inform + STUN + discovery from the UniFi device VLAN(s).
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "8080",
      source = "+unifi-device-sources", comment = "Device inform (UniFi devices)" },
      { type = "in", action = "ACCEPT", proto = "udp", dport = "3478",
      source = "+unifi-device-sources", comment = "STUN (UniFi devices)" },
      { type = "in", action = "ACCEPT", proto = "udp", dport = "10001",
      source = "+unifi-device-sources", comment = "Device adoption (UniFi devices)" },
      { type = "in", action = "ACCEPT", proto = "udp", dport = "10003",
      source = "+unifi-device-sources", comment = "Device discovery (UniFi devices)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    avahi = [
      # mDNS reflector: receives/reflects mDNS on eth0 (VLAN 90). The extra
      # link-only NICs (VLANs 100/150/152/120/122/132) are firewall=false (a
      # deny-by-default guest firewall drops multicast), so only eth0 is filtered.
      { type = "in", action = "ACCEPT", proto = "udp", dport = "5353",
      comment = "mDNS (reflector)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    infra-core = [
      # NTP time server: UDP 123 from the server VLANs only.
      { type = "in", action = "ACCEPT", proto = "udp", dport = "123",
      source = "+ntp-sources", comment = "NTP (server VLANs)" },
      # Postfix relay: accepts SMTP on 25 from the internal networks.
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "25",
      source = "+mail-relay-sources", comment = "SMTP relay (internal)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    haos = [
      # Home Assistant UI (web dashboard) from the management VLANs only. HAOS
      # serves the dashboard via its supervisor ingress on 80/443, not 8123.
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "80,443",
      source = "+haos-ui-sources", comment = "Home Assistant UI (mgmt)" },
      # Home Assistant UI from the WireGuard overlay (all peers, presence/proximity).
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "80,443",
      source = "+wg-sources", comment = "Home Assistant UI (WireGuard)" },
      # IoT integrations from the IoT VLANs (MQTT/Matter/zigbee2mqtt, Chromecast
      # and Nest on 150/152). Egress stays ACCEPT so HAOS reaches them too;
      # these cover the new-inbound direction (mDNS replies, cast control,
      # Matter). Established reply traffic is allowed by PVE automatically.
      { type = "in", action = "ACCEPT", proto = "udp", dport = "5353",
      source = "+haos-iot-sources", comment = "mDNS/Chromecast discovery (IoT 150/152)" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "1883,8883",
      source = "+haos-iot-sources", comment = "MQTT (IoT 150/152)" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "5540",
      source = "+haos-iot-sources", comment = "Matter operational (IoT 150/152)" },
      { type = "in", action = "ACCEPT", proto = "udp", dport = "5540",
      source = "+haos-iot-sources", comment = "Matter commissioning (IoT 150/152)" },
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "8008,8009,8443",
      source = "+haos-iot-sources", comment = "Chromecast control (IoT 150/152)" },
      { type = "in", action = "ACCEPT", proto = "udp", dport = "1900",
      source = "+haos-iot-sources", comment = "SSDP (IoT 150/152)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
    mqtt = [
      # MQTT broker (mosquitto): 1883 open only to the known broker clients
      # (HA - Pi container/haos01 - and the future zigbee2mqtt container).
      { type = "in", action = "ACCEPT", proto = "tcp", dport = "1883",
      source = "+mqtt-client-sources", comment = "MQTT (broker clients)" },
      { type = "in", action = "DROP", comment = "Deny other inbound" },
    ]
  }
}