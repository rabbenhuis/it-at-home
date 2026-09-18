terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.107.0"
    }
  }
}

# The API token id (terraform@pve!infra) is identical on every node; only the
# secret differs per node.
variable "pm_api_token_id" {
  type      = string
  sensitive = true
}

variable "pm_api_token_secret_pve1" {
  type      = string
  sensitive = true
}

# TEMP pve2: not installed yet — the build script only sets the selected node's
# secret, so this stays empty for pve1 builds (never prompted). Once pve2 is up,
# the provider uses it when target=pve2.
variable "pm_api_token_secret_pve2" {
  type      = string
  sensitive = true
  default   = ""
}

# Selected per build by scripts/build-template.sh
variable "template_role" {
  description = "Which template to build: native, podman, docker or vm"
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

variable "target" {
  description = "PVE node to build on: pve1 (amd64) or pve2 (arm64)"
  type        = string
  default     = "pve1"
  validation {
    condition     = contains(["pve1", "pve2"], var.target)
    error_message = "target must be pve1 or pve2."
  }
}

module "cluster" {
  source = "./modules/cluster-data"
}

locals {
  node = module.cluster.nodes[var.target]
}

provider "proxmox" {
  endpoint  = local.node.endpoint
  api_token = var.target == "pve1" ? "${var.pm_api_token_id}=${var.pm_api_token_secret_pve1}" : "${var.pm_api_token_id}=${var.pm_api_token_secret_pve2}"
  insecure  = true
}

module "template_native" {
  source = "./modules/lxc-template"

  count = var.template_role == "native" ? 1 : 0

  name               = "debian13-native"
  template_version   = var.template_version
  vmid               = var.template_vmid
  node_name          = local.node.node_name
  role               = "native"
  base_template_file = local.node.lxc_ostemplate
  base_clone_id      = 0
  hostname           = "tmpl-debian13-native-build.abbenhuis.internal"
  nameserver         = local.node.nameserver
  searchdomain       = "abbenhuis.internal"
  ip                 = local.node.ip.native
  gateway            = local.node.gateway
  ssh_keys           = module.cluster.ssh_keys
  unprivileged       = true
  swap               = 0
  nesting            = false
  fuse               = false
  keyctl             = false
  cores              = 1
  memory             = 512
  disk_size          = 8
  disk_datastore     = local.node.disk_datastore
  bridge             = local.node.bridge
  vlan_id            = local.node.vlan_id
  firewall           = true
  ostype             = "debian"
  architecture       = local.node.architecture
}

module "template_podman" {
  source = "./modules/lxc-template"

  count = var.template_role == "podman" ? 1 : 0

  name               = "debian13-podman"
  template_version   = var.template_version
  vmid               = var.template_vmid
  node_name          = local.node.node_name
  role               = "podman"
  base_template_file = ""
  base_clone_id      = var.native_template_vmid
  hostname           = "tmpl-debian13-podman-build.abbenhuis.internal"
  nameserver         = local.node.nameserver
  searchdomain       = "abbenhuis.internal"
  ip                 = local.node.ip.podman
  gateway            = local.node.gateway
  ssh_keys           = module.cluster.ssh_keys
  unprivileged       = true
  swap               = 0
  nesting            = true
  fuse               = false
  keyctl             = false
  cores              = 2
  memory             = 1024
  disk_size          = 16
  disk_datastore     = local.node.disk_datastore
  bridge             = local.node.bridge
  vlan_id            = local.node.vlan_id
  firewall           = true
  ostype             = "debian"
  architecture       = local.node.architecture
}

module "template_docker" {
  source = "./modules/lxc-template"

  count = var.template_role == "docker" ? 1 : 0

  name               = "debian13-docker"
  template_version   = var.template_version
  vmid               = var.template_vmid
  node_name          = local.node.node_name
  role               = "docker"
  base_template_file = ""
  base_clone_id      = var.native_template_vmid
  hostname           = "tmpl-debian13-docker-build.abbenhuis.internal"
  nameserver         = local.node.nameserver
  searchdomain       = "abbenhuis.internal"
  ip                 = local.node.ip.docker
  gateway            = local.node.gateway
  ssh_keys           = module.cluster.ssh_keys
  unprivileged       = true
  nesting            = true
  fuse               = false
  keyctl             = false
  cores              = 1
  memory             = 512
  swap               = 0
  disk_size          = 16
  disk_datastore     = local.node.disk_datastore
  bridge             = local.node.bridge
  vlan_id            = local.node.vlan_id
  firewall           = true
  ostype             = "debian"
  architecture       = local.node.architecture
}

module "template_vm" {
  source = "./modules/vm-template"

  count = var.template_role == "vm" ? 1 : 0

  name                = "debian13-vm"
  template_version    = var.template_version
  vmid                = var.template_vmid
  node_name           = local.node.node_name
  hostname            = "tmpl-debian13-vm-build"
  cloud_image_file_id = local.node.vm_cloudimage
  nameserver          = local.node.nameserver
  searchdomain        = "abbenhuis.internal"
  ip                  = local.node.ip.vm
  gateway             = local.node.gateway
  ssh_keys            = module.cluster.ssh_keys
  cores               = 2
  memory              = 2048
  disk_size           = 20
  disk_datastore      = local.node.disk_datastore
  bridge              = local.node.bridge
  vlan_id             = local.node.vlan_id
  firewall            = true
  ostype              = "l26"
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

output "vm_ip" {
  value = try(module.template_vm[0].ip, "")
}
