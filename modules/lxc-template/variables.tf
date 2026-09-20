variable "name" {
  description = "Template base name, e.g. debian13-native"
  type        = string
}

variable "template_version" {
  description = "Template version suffix, e.g. 1"
  type        = string
}

variable "vmid" {
  description = "Container/template ID"
  type        = number
}

variable "node_name" {
  type = string
}

variable "role" {
  description = "Build role: native, podman or docker (drives the ansible playbook)"
  type        = string
}

variable "base_template_file" {
  description = "Upstream template file id, e.g. nas:vztmpl/... Use empty when cloning."
  type        = string
  default     = ""
}

variable "base_clone_id" {
  description = "VMID of the template to clone from. Use 0 when creating from base_template_file."
  type        = number
  default     = 0
}

variable "hostname" {
  type = string
}

variable "nameserver" {
  type = string
}

variable "searchdomain" {
  type = string
}

variable "ip" {
  description = "Static IPv4 address in CIDR notation"
  type        = string
}

variable "gateway" {
  type = string
}

variable "ssh_keys" {
  type = list(string)
}

variable "unprivileged" {
  type    = bool
  default = true
}

variable "nesting" {
  type    = bool
  default = false
}

variable "fuse" {
  type    = bool
  default = false
}

variable "keyctl" {
  type    = bool
  default = false
}

variable "cores" {
  type    = number
  default = 1
}

variable "memory" {
  type    = number
  default = 512
}

variable "swap" {
  type    = number
  default = 0
}

variable "disk_size" {
  type    = number
  default = 8
}

variable "disk_datastore" {
  type    = string
  default = "local-ssd"
}

variable "bridge" {
  type    = string
  default = "vmbr0"
}

variable "vlan_id" {
  type    = number
  default = 0
}

variable "firewall" {
  type    = bool
  default = false
}

variable "ostype" {
  type    = string
  default = "debian"
}

variable "architecture" {
  type    = string
  default = "amd64"
}