variable "description" {
  type    = string
  default = "Managed by Terraform (deployed)"
}

variable "name" {
  description = "Host name (map key in deploy/deployments.tf)"
  type        = string
}

variable "type" {
  description = "lxc or vm"
  type        = string
}

variable "vmid" {
  description = "Container/VM VMID"
  type        = number
}

variable "template_vmid" {
  description = "VMID of the template to clone from (9000 native / 9010 podman / 9020 docker / 9200 vm)"
  type        = number
}

variable "node_name" {
  type = string
}

variable "architecture" {
  type    = string
  default = "amd64"
}

variable "hostname" {
  description = "Hostname (short name; dns.domain is the search domain)"
  type        = string
}

variable "nameserver" {
  type = list(string)
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
  type    = list(string)
  default = []
}

variable "on_boot" {
  type    = bool
  default = true
}

variable "startup" {
  description = "Startup/shutdown behavior: { order, up_delay?, down_delay? }. Omit to leave unset."
  type = object({
    order      = number
    up_delay   = optional(number)
    down_delay = optional(number)
  })
  default = null
}

variable "unprivileged" {
  type    = bool
  default = true
}

variable "nesting" {
  type    = bool
  default = null
}

variable "fuse" {
  type    = bool
  default = null
}

variable "keyctl" {
  type    = bool
  default = null
}

variable "cores" {
  description = "CPU cores; 0 inherits the template value"
  type        = number
  default     = 0
}

variable "memory" {
  description = "Dedicated memory in MB; 0 inherits the template value"
  type        = number
  default     = 0
}

variable "cpuunits" {
  description = "CPU weight for fair-share scheduling; 0 inherits the template value (default 1024)"
  type        = number
  default     = 0
}

variable "swap" {
  type    = number
  default = 0
}

variable "disk_size" {
  description = "Rootfs/disk size in GB (LXC only); 0 inherits the template value"
  type        = number
  default     = 0
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
  type = number
}

variable "firewall" {
  type    = bool
  default = true
}

variable "firewall_rules" {
  description = "Complete PVE firewall rule set for this host (list of rule objects). Empty = no rules."
  type = list(object({
    type    = string
    action  = string
    comment = optional(string)
    proto   = optional(string)
    dport   = optional(string)
    sport   = optional(string)
    source  = optional(string)
    dest    = optional(string)
    iface   = optional(string)
    log     = optional(string)
  }))
  default = []
}