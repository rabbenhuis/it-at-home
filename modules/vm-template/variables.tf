variable "name" {
  description = "Template base name, e.g. debian13-vm"
  type        = string
}

variable "template_version" {
  description = "Template version suffix, e.g. 1"
  type        = string
}

variable "vmid" {
  type = number
}

variable "node_name" {
  type = string
}

variable "hostname" {
  description = "VM name / cloud-init hostname during build"
  type        = string
}

variable "cloud_image_file_id" {
  description = "ID of the downloaded cloud image, e.g. local:iso/debian-13-generic-amd64.qcow2"
  type        = string
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

variable "cores" {
  type    = number
  default = 2
}

variable "memory" {
  type    = number
  default = 2048
}

variable "disk_size" {
  type    = number
  default = 20
}

variable "disk_datastore" {
  type    = string
  default = "local-lvm"
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
  default = "l26"
}

variable "architecture" {
  type    = string
  default = "amd64"
}