output "nodes" {
  description = "Per-node infrastructure settings (endpoint, node name, arch, storage, network)"
  value = {
    pve1 = {
      # Endpoint by IP: the .abbenhuis.internal name isn't in any DNS/hosts, so
      # hostname resolution on the control host is unreliable.
      endpoint        = "https://192.168.70.64:8006/"
      node_name       = "bm-pve-prd-01"
      architecture    = "amd64"
      disk_datastore  = "local-ssd"
      usb_datastore   = "local-usbssd"
      image_datastore = "nas"
      bridge          = "vmbr0"
      vlan_id         = 70
      nameserver      = "192.168.70.1"
      gateway         = "192.168.70.1"
      lxc_ostemplate  = "nas:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
      vm_cloudimage   = "nas:import/debian-13-genericcloud-amd64.qcow2"
      haos_image      = "nas:import/haos_ova-18.2.qcow2"
      ip = {
        native = "192.168.70.90/24"
        podman = "192.168.70.91/24"
        docker = "192.168.70.92/24"
        vm     = "192.168.70.93/24"
      }
    }
    pve2 = {
      # Replace with the node IP once the Pi becomes pve2 (same as pve1: no
      # reliable hostname resolution for .abbenhuis.internal).
      endpoint       = "https://bm-pve-prd-02.abbenhuis.internal:8006/"
      node_name      = "bm-pve-prd-02"
      architecture   = "arm64"
      disk_datastore = "local"
      # Placeholder until pve2 is installed: same storage id as pve1 for now,
      # adjust once the Pi has its own external SSD configured.
      usb_datastore   = "local-usbssd"
      image_datastore = "nas"
      bridge          = "vmbr0"
      vlan_id         = 70
      nameserver      = "192.168.70.1"
      gateway         = "192.168.70.1"
      # arm64 artifacts must be provisioned on pve2's nas first:
      #   pveam available | grep arm64            (confirm exact version)
      #   pveam download nas <debian-13-..._arm64.tar.zst>
      #   curl -o /mnt/pve/nas/import/debian-13-genericcloud-arm64.qcow2 \
      #     https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-arm64.qcow2
      lxc_ostemplate = "nas:vztmpl/debian-13-standard_13.6-1_arm64.tar.zst"
      vm_cloudimage  = "nas:import/debian-13-genericcloud-arm64.qcow2"
      # HAOS on arm64/QEMU is not officially supported; placeholder for now.
      haos_image = "nas:import/haos_generic-aarch64-18.2.qcow2"
      ip = {
        native = "192.168.70.90/24"
        podman = "192.168.70.91/24"
        docker = "192.168.70.92/24"
        vm     = "192.168.70.93/24"
      }
    }
  }
}

output "vlans" {
  description = "Global VLAN registry keyed by VLAN ID. Every deployed host resolves gateway/nameserver/dns_zone from here."
  value = {
    37 = {
      name       = "Network Management"
      subnet     = "192.168.37.0/24"
      gateway    = "192.168.37.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "mgmt.abbenhuis.internal"
    }
    70 = {
      name       = "Hypervisor Plane"
      subnet     = "192.168.70.0/24"
      gateway    = "192.168.70.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "hyper.abbenhuis.internal"
    }
    75 = {
      name       = "Security Hypervisor Plane"
      subnet     = "192.168.75.0/24"
      gateway    = "192.168.75.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "sec-hyper.abbenhuis.internal"
    }
    80 = {
      name       = "Security Services"
      subnet     = "192.168.80.0/24"
      gateway    = "192.168.80.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "sec.abbenhuis.internal"
    }
    90 = {
      name       = "infrastructure"
      subnet     = "192.168.90.0/24"
      gateway    = "192.168.90.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "infra.abbenhuis.internal"
    }
    95 = {
      name       = "Operations"
      subnet     = "192.168.95.0/24"
      gateway    = "192.168.95.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "ops.abbenhuis.internal"
    }
    100 = {
      name       = "Applications"
      subnet     = "192.168.100.0/24"
      gateway    = "192.168.100.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "apps.abbenhuis.internal"
    }
    115 = {
      name       = "Observability"
      subnet     = "192.168.115.0/24"
      gateway    = "192.168.115.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "obs.abbenhuis.internal"
    }
    120 = {
      name       = "Wired Clients"
      subnet     = "192.168.120.0/24"
      gateway    = "192.168.120.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "clients.abbenhuis.internal"
    }
    122 = {
      name       = "Wireless Clients"
      subnet     = "192.168.122.0/24"
      gateway    = "192.168.122.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "clients.abbenhuis.internal"
    }
    132 = {
      name       = "Private WLAN"
      subnet     = "192.168.132.0/24"
      gateway    = "192.168.132.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "clients.abbenhuis.internal"
    }
    142 = {
      name       = "Guest WLAN"
      subnet     = "192.168.142.0/24"
      gateway    = "192.168.142.1"
      nameserver = ["192.168.142.1"]
      dns_zone   = "guest.abbenhuis.internal"
    }
    150 = {
      name       = "IoT Platform"
      subnet     = "192.168.150.0/24"
      gateway    = "192.168.150.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "iot-platform.abbenhuis.internal"
    }
    152 = {
      name       = "IoT Devices"
      subnet     = "192.168.152.0/24"
      gateway    = "192.168.152.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "iot.abbenhuis.internal"
    }
    160 = {
      name       = "Gaming"
      subnet     = "192.168.160.0/24"
      gateway    = "192.168.160.1"
      nameserver = ["192.168.90.40", "192.168.90.42"]
      dns_zone   = "gaming.abbenhuis.internal"
    }
  }
}

output "ssh_keys" {
  description = "SSH public keys injected into templates / VM deployments"
  value = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAgEAqa2AH3zrgqR4DvUVgEhqdts3yFHvwsPw2KM3x8OiX3MYttUn9Hp64cTTdhbCIQ+waBTHH9ccJq4E0NEwQZ5HRyjO7jeIjDDGN2VDzWYUaZYgQFmeOobYfOhAXnR6As3uzTeGMMix8aQv8ll2g0h3pXNorPwuDn9hf3A9XpLiNacf/VrNdWZI9QA0Lq5NPWb2aFrgwyqn+DCNCdzUt/fIliTyB69QWXEnadeZAT4S8arzyFklzSrvkc1kVogqL8pwyg603u+RgvXfGjKBRzUT2rfCOAGPRUO5uGoQOBJ9zJrwZw+kzbQTv2KhtmAriKMWnC8M2olM5c9J00gTY+3AgXvdSCP9OFWe1hj+IqdLoltSfdkqRgUk4+xXLpYklQWPWSFOpOzDWZ9Cgtn46QWJ1jZY5obxe6GSDbswA4AvawbM2GqJT6MIWt30j0Xpp6O0icPK7OVWNayHrK//UbmdsW2xvdS5WNMYP1CPKKHkjz8STCH264KOHTKqOsXHHKChEA0faK/DL1bfA591LgXCV/np3QJHjltecLMVlNS3f+ewdrd/UTZENpnj1H/9YB4SwCWWWavOGeZcUV6Jn4wAfWjRXnhXovKJDr74qo9L32MXeoE51trQpDvrXo5LSz3krEhRxgXHRFS3riO5Pt2jhARedFG1KThrfVIQaO5PMDU= richard@abbenhuis.net",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGjLSZC66g5QuBZZzf8H957i4aWdM2RR4txqGyZKWsLk homedevsecopsstack-devuser",
  ]
}
