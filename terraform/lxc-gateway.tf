module "gateway" {
  source = "./modules/lxc"

  name        = "gateway"
  description = "Traefik reverse proxy + Cloudflare tunnel"
  vm_id       = var.lxc_vm_ids["gateway"]

  cpu_cores        = 2
  memory_dedicated = 512
  memory_swap      = 256
  disk_size        = 8

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["gateway"]
  ip_eth1         = local.ip_eth1["gateway"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key
}
