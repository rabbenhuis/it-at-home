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

module "cluster" {
  source = "../modules/cluster-data"
}

# Deployments span both nodes simultaneously, so each node gets its own
# provider alias. One module per node (for_each keyed by host name) keeps the
# `-target` addresses simple: module.deploy_pve1 / module.deploy_pve2 for a
# whole node, module.deploy_pve1["web1"] for a single host.
provider "proxmox" {
  alias     = "pve1"
  endpoint  = module.cluster.nodes.pve1.endpoint
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = true
}

provider "proxmox" {
  alias     = "pve2"
  endpoint  = module.cluster.nodes.pve2.endpoint
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"
  insecure  = true
}

locals {
  pve1_hosts = { for name, h in local.deployments : name => h if h.target == "pve1" }
  pve2_hosts = { for name, h in local.deployments : name => h if h.target == "pve2" }
}

module "deploy_pve1" {
  source    = "../modules/deploy"
  providers = { proxmox = proxmox.pve1 }

  for_each = local.pve1_hosts

  name           = each.key
  type           = each.value.type
  vmid           = each.value.vmid
  template_vmid  = each.value.template_vmid
  node_name      = module.cluster.nodes.pve1.node_name
  architecture   = module.cluster.nodes.pve1.architecture
  hostname       = each.key
  nameserver     = module.cluster.vlans[each.value.vlan_id].nameserver
  searchdomain   = module.cluster.vlans[each.value.vlan_id].dns_zone
  ip             = each.value.ip
  gateway        = module.cluster.vlans[each.value.vlan_id].gateway
  ssh_keys       = module.cluster.ssh_keys
  on_boot        = try(each.value.on_boot, true)
  startup        = try(each.value.startup, null)
  unprivileged   = try(each.value.unprivileged, true)
  nesting        = try(each.value.nesting, null)
  fuse           = try(each.value.fuse, null)
  keyctl         = try(each.value.keyctl, null)
  cores          = try(each.value.cores, 0)
  memory         = try(each.value.memory, 0)
  swap           = 0
  disk_size      = try(each.value.disk_size, 0)
  disk_datastore = module.cluster.nodes.pve1.disk_datastore
  bridge         = module.cluster.nodes.pve1.bridge
  vlan_id        = each.value.vlan_id
  firewall       = true
  firewall_rules = length(try(local.firewall_rules[each.value.role], [])) > 0 ? concat(local.firewall_mgmt_base, local.firewall_rules[each.value.role]) : []
  description    = try(each.value.description, "Managed by Terraform (deployed from template vmid ${each.value.template_vmid})")
}

module "deploy_pve2" {
  source    = "../modules/deploy"
  providers = { proxmox = proxmox.pve2 }

  for_each = local.pve2_hosts

  name           = each.key
  type           = each.value.type
  vmid           = each.value.vmid
  template_vmid  = each.value.template_vmid
  node_name      = module.cluster.nodes.pve2.node_name
  architecture   = module.cluster.nodes.pve2.architecture
  hostname       = each.key
  nameserver     = module.cluster.vlans[each.value.vlan_id].nameserver
  searchdomain   = module.cluster.vlans[each.value.vlan_id].dns_zone
  ip             = each.value.ip
  gateway        = module.cluster.vlans[each.value.vlan_id].gateway
  ssh_keys       = module.cluster.ssh_keys
  on_boot        = try(each.value.on_boot, true)
  startup        = try(each.value.startup, null)
  unprivileged   = try(each.value.unprivileged, true)
  nesting        = try(each.value.nesting, null)
  fuse           = try(each.value.fuse, null)
  keyctl         = try(each.value.keyctl, null)
  cores          = try(each.value.cores, 0)
  memory         = try(each.value.memory, 0)
  swap           = 0
  disk_size      = try(each.value.disk_size, 0)
  disk_datastore = module.cluster.nodes.pve2.disk_datastore
  bridge         = module.cluster.nodes.pve2.bridge
  vlan_id        = each.value.vlan_id
  firewall       = true
  firewall_rules = length(try(local.firewall_rules[each.value.role], [])) > 0 ? concat(local.firewall_mgmt_base, local.firewall_rules[each.value.role]) : []
  description    = try(each.value.description, "Managed by Terraform (deployed from template vmid ${each.value.template_vmid})")
}

output "hosts" {
  description = "All hosts in the deployment map (name -> type, node, vlan, ip, vmid, playbook)"
  value = {
    for name, h in local.deployments : name => {
      type     = h.type
      target   = h.target
      vlan_id  = h.vlan_id
      vmid     = h.vmid
      ip       = h.ip
      playbook = try(local.roles[try(h.role, "")], "")
    }
  }
}