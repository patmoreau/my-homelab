output "vm_id" {
  value = proxmox_virtual_environment_container.this.vm_id
}

output "ip" {
  value = var.ip_eth0
}
