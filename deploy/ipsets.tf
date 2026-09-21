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

# AdGuard node IPs - the only sources allowed to query the unbound resolvers.
resource "proxmox_virtual_environment_firewall_ipset" "adguard_servers" {
  provider = proxmox.pve1

  name    = "adguard-servers"
  comment = "AdGuard Home servers (may query the unbound resolvers)"

  dynamic "cidr" {
    for_each = local.adguard_dns_servers
    content {
      name    = cidr.value.ip
      comment = cidr.value.name
    }
  }
}

# VLANs hosting UniFi managed devices (switches/APs) - the only sources that
# may reach the UniFi OS Server on inform/adoption/STUN/discovery ports.
# Referenced from the unifi role's rules as source "+unifi-device-sources".
resource "proxmox_virtual_environment_firewall_ipset" "unifi_device_sources" {
  provider = proxmox.pve1

  name    = "unifi-device-sources"
  comment = "UniFi managed devices (may adopt to the UniFi OS Server)"

  dynamic "cidr" {
    for_each = local.unifi_device_sources
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}

# Management VLANs allowed to reach the Home Assistant UI (port 8123).
# Referenced from the haos role's rule as source "+haos-ui-sources".
resource "proxmox_virtual_environment_firewall_ipset" "haos_ui_sources" {
  provider = proxmox.pve1

  name    = "haos-ui-sources"
  comment = "VLANs allowed to reach the Home Assistant UI"

  dynamic "cidr" {
    for_each = local.firewall_haos_ui_sources
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}

# IoT VLANs that Home Assistant integrates with (MQTT/Matter/zigbee2mqtt,
# Chromecast/Nest devices). Referenced from the haos role's IoT rules as
# source "+haos-iot-sources".
resource "proxmox_virtual_environment_firewall_ipset" "haos_iot_sources" {
  provider = proxmox.pve1

  name    = "haos-iot-sources"
  comment = "IoT VLANs Home Assistant integrates with"

  dynamic "cidr" {
    for_each = local.firewall_haos_iot_sources
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}

# WireGuard overlay clients (wg-home, 172.18.10.0/24) - all peers may reach the
# HAOS UI. Also folded into adguard_dns_sources for DNS. Referenced from the
# haos role's rule as source "+wg-sources".
resource "proxmox_virtual_environment_firewall_ipset" "wg_sources" {
  provider = proxmox.pve1

  name    = "wg-sources"
  comment = "WireGuard clients (wg-home)"

  dynamic "cidr" {
    for_each = local.firewall_wg_client_cidrs
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}

# WireGuard admin peers - wg-darth-sidious (private phone) and wg-laptop may
# reach the UniFi controller. Referenced from the unifi role's rule as "+wg-admin".
resource "proxmox_virtual_environment_firewall_ipset" "wg_admin" {
  provider = proxmox.pve1

  name    = "wg-admin"
  comment = "WireGuard peers with admin service access"

  dynamic "cidr" {
    for_each = local.firewall_wg_admin_cidrs
    content {
      name    = cidr.value.subnet
      comment = cidr.value.name
    }
  }
}