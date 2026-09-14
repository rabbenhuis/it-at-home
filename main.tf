terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.107.0"
    }
  }
}

variable "pm_api_token_id" {
  type      = string
  sensitive = true
}

variable "pm_api_token_secret" {
  type      = string
  sensitive = true
}

# Selected per build by scripts/build-template.sh
variable "template_role" {
  description = "Which template to build: native, podman or docker"
  type        = string
  default     = "native"
}

variable "template_version" {
  type    = string
  default = "1"
}

variable "template_vmid" {
  type    = number
  default = 9000
}

variable "native_template_vmid" {
  description = "VMID of the current native template (clone source for podman/docker)"
  type        = number
  default     = 9000
}

provider "proxmox" {
  endpoint  = "https://bm-pve-prd-01.abbenhuis.internal:8006/"
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = true
}

locals {
  ssh_keys = [
    "ssh-rsa AAAAB3NzaC1yc2EAAAABJQAAAgEAqa2AH3zrgqR4DvUVgEhqdts3yFHvwsPw2KM3x8OiX3MYttUn9Hp64cTTdhbCIQ+waBTHH9ccJq4E0NEwQZ5HRyjO7jeIjDDGN2VDzWYUaZYgQFmeOobYfOhAXnR6As3uzTeGMMix8aQv8ll2g0h3pXNorPwuDn9hf3A9XpLiNacf/VrNdWZI9QA0Lq5NPWb2aFrgwyqn+DCNCdzUt/fIliTyB69QWXEnadeZAT4S8arzyFklzSrvkc1kVogqL8pwyg603u+RgvXfGjKBRzUT2rfCOAGPRUO5uGoQOBJ9zJrwZw+kzbQTv2KhtmAriKMWnC8M2olM5c9J00gTY+3AgXvdSCP9OFWe1hj+IqdLoltSfdkqRgUk4+xXLpYklQWPWSFOpOzDWZ9Cgtn46QWJ1jZY5obxe6GSDbswA4AvawbM2GqJT6MIWt30j0Xpp6O0icPK7OVWNayHrK//UbmdsW2xvdS5WNMYP1CPKKHkjz8STCH264KOHTKqOsXHHKChEA0faK/DL1bfA591LgXCV/np3QJHjltecLMVlNS3f+ewdrd/UTZENpnj1H/9YB4SwCWWWavOGeZcUV6Jn4wAfWjRXnhXovKJDr74qo9L32MXeoE51trQpDvrXo5LSz3krEhRxgXHRFS3riO5Pt2jhARedFG1KThrfVIQaO5PMDU= richard@abbenhuis.net",
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGjLSZC66g5QuBZZzf8H957i4aWdM2RR4txqGyZKWsLk homedevsecopsstack-devuser",
  ]
}

module "template_native" {
  source = "./modules/lxc-template"

  count = var.template_role == "native" ? 1 : 0

  name               = "debian13-native"
  template_version   = var.template_version
  vmid               = var.template_vmid
  node_name          = "bm-pve-prd-01"
  role               = "native"
  base_template_file = "nas:vztmpl/debian-13-standard_13.6-1_amd64.tar.zst"
  base_clone_id      = 0
  hostname           = "tmpl-debian13-native-build.abbenhuis.internal"
  nameserver         = "192.168.70.1"
  searchdomain       = "abbenhuis.internal"
  ip                 = "192.168.70.90/24"
  gateway            = "192.168.70.1"
  ssh_keys           = local.ssh_keys
  unprivileged       = true
  nesting            = false
  fuse               = false
  keyctl             = false
  cores              = 1
  memory             = 512
  swap               = 0
  disk_size          = 8
  disk_datastore     = "local-lvm"
  bridge             = "vmbr0"
  vlan_id            = 70
  firewall           = true
  ostype             = "debian"
}

module "template_podman" {
  source = "./modules/lxc-template"

  count = var.template_role == "podman" ? 1 : 0

  name               = "debian13-podman"
  template_version   = var.template_version
  vmid               = var.template_vmid
  node_name          = "bm-pve-prd-01"
  role               = "podman"
  base_template_file = ""
  base_clone_id      = var.native_template_vmid
  hostname           = "tmpl-debian13-podman-build.abbenhuis.internal"
  nameserver         = "192.168.70.1"
  searchdomain       = "abbenhuis.internal"
  ip                 = "192.168.70.91/24"
  gateway            = "192.168.70.1"
  ssh_keys           = local.ssh_keys
  unprivileged       = true
  nesting            = true
  fuse               = false
  keyctl             = false
  cores              = 2
  memory             = 1024
  swap               = 0
  disk_size          = 16
  disk_datastore     = "local-lvm"
  bridge             = "vmbr0"
  vlan_id            = 70
  firewall           = true
  ostype             = "debian"
}

module "template_docker" {
  source = "./modules/lxc-template"

  count = var.template_role == "docker" ? 1 : 0

  name               = "debian13-docker"
  template_version   = var.template_version
  vmid               = var.template_vmid
  node_name          = "bm-pve-prd-01"
  role               = "docker"
  base_template_file = ""
  base_clone_id      = var.native_template_vmid
  hostname           = "tmpl-debian13-docker-build.abbenhuis.internal"
  nameserver         = "192.168.70.1"
  searchdomain       = "abbenhuis.internal"
  ip                 = "192.168.70.92/24"
  gateway            = "192.168.70.1"
  ssh_keys           = local.ssh_keys
  unprivileged       = true
  nesting            = true
  fuse               = false
  keyctl             = false
  cores              = 1
  memory             = 512
  swap               = 0
  disk_size          = 16
  disk_datastore     = "local-lvm"
  bridge             = "vmbr0"
  vlan_id            = 70
  firewall           = true
  ostype             = "debian"
}

output "native_ip" {
  value = try(module.template_native[0].ip, "")
}

output "podman_ip" {
  value = try(module.template_podman[0].ip, "")
}

output "docker_ip" {
  value = try(module.template_docker[0].ip, "")
}
