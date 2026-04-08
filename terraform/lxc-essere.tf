module "essere" {
  source = "./modules/lxc"

  name        = "essere"
  description = "LXC Essere (essere.ca)"
  vm_id       = var.lxc_vm_ids["essere"]

  cpu_cores        = 2
  memory_dedicated = 1024
  memory_swap      = 512
  disk_size        = 16

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["essere"]
  ip_eth1         = local.ip_eth1["essere"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  mounts = [
    { volume = "local-lvm:vm-${var.lxc_vm_ids["essere"]}-essere-data", mp = "/data", backup = true },
  ]
}
