output "nodes" {
  description = "Per-node infrastructure settings (endpoint, node name, arch, storage, network)"
  value = {
    pve1 = {
      endpoint        = "https://bm-pve-prd-01.abbenhuis.internal:8006/"
      node_name       = "bm-pve-prd-01"
      architecture    = "amd64"
      disk_datastore  = "local-lvm"
      image_datastore = "nas"
      bridge          = "vmbr0"
      vlan_id         = 70
      nameserver      = "192.168.70.1"
      gateway         = "192.168.70.1"
      lxc_ostemplate  = "nas:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
      vm_cloudimage   = "nas:import/debian-13-genericcloud-amd64.qcow2"
      ip = {
        native = "192.168.70.90/24"
        podman = "192.168.70.91/24"
        docker = "192.168.70.92/24"
        vm     = "192.168.70.93/24"
      }
    }
    pve2 = {
      endpoint        = "https://bm-pve-prd-02.abbenhuis.internal:8006/"
      node_name       = "bm-pve-prd-02"
      architecture    = "arm64"
      disk_datastore  = "local"
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
    70 = {
      name       = "mgmt"
      subnet     = "192.168.70.0/24"
      gateway    = "192.168.70.1"
      nameserver = ["192.168.70.1"]
      dns_zone   = "abbenhuis.internal"
    }
    90 = {
      name       = "infrastructure"
      subnet     = "192.168.90.0/24"
      gateway    = "192.168.90.1"
      nameserver = ["192.168.90.40", "192.168.90.42", "192.168.90.1"]
      dns_zone   = "infra.abbenhuis.net"
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
