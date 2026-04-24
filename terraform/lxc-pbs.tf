module "pbs" {
  source = "./modules/lxc"

  name        = "pbs"
  description = "Proxmox Backup Server"
  vm_id       = var.lxc_vm_ids["pbs"]

  cpu_cores        = 2
  memory_dedicated = 2048  # MiB
  memory_swap      = 512   # MiB
  disk_size        = 8     # GiB

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["pbs"]
  ip_eth1         = local.ip_eth1["pbs"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key
}
