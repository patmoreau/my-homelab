module "open_webui" {
  source = "./modules/lxc"

  name        = "open-webui"
  description = "Open WebUI frontend"
  vm_id       = var.lxc_vm_ids["open-webui"]

  cpu_cores        = 2
  memory_dedicated = 2048
  memory_swap      = 1024
  disk_size        = 10

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["open-webui"]
  ip_eth1         = local.ip_eth1["open-webui"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  mounts = [
    { host = "/mnt/containers/lxc-open-webui", mp = "/data" }
  ]
}
