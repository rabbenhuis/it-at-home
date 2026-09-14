output "template_name" {
  value = "tmpl-${var.name}-v${var.template_version}"
}

output "vmid" {
  value = var.vmid
}

output "ip" {
  value = var.ip
}