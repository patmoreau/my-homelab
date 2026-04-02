output "lxc_ips" {
  value = {
    gateway    = module.gateway.ip
    media      = module.media.ip
    essere     = module.essere.ip
    monitoring = module.monitoring.ip
    tools      = module.tools.ip
  }
}

output "lxc_ids" {
  value = {
    gateway    = module.gateway.vm_id
    media      = module.media.vm_id
    essere     = module.essere.vm_id
    monitoring = module.monitoring.vm_id
    tools      = module.tools.vm_id
  }
}
