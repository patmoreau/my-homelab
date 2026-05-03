module "ollama" {
  source = "./modules/lxc"

  name        = "ollama"
  description = "Ollama LLM inference server"
  vm_id       = var.lxc_vm_ids["ollama"]

  cpu_cores        = 4
  memory_dedicated = 16384
  memory_swap      = 1024
  disk_size        = 75

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["ollama"]
  ip_eth1         = local.ip_eth1["ollama"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  gpu_passthrough = true
  gpu_render_gid  = 993
}
