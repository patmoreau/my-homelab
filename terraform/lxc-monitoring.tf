module "monitoring" {
  source = "./modules/lxc"

  name        = "monitoring"
  description = "Loki + Grafana + Prometheus monitoring stack"
  vm_id       = var.lxc_vm_ids["monitoring"]

  cpu_cores        = 2
  memory_dedicated = 512
  memory_swap      = 256
  disk_size        = 8

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["monitoring"]
  ip_eth1         = local.ip_eth1["monitoring"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  mounts = [
    { host = "/mnt/containers/lxc-monitoring", mp = "/data" },
  ]
}
