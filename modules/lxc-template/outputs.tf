output "template_name" {
  value = "tmpl-${var.name}-v${var.template_version}"
}

output "vmid" {
  value = var.vmid
}

output "vm_id" {
  value = proxmox_virtual_environment_container.build.id
}

output "ip" {
  value = var.ip
}