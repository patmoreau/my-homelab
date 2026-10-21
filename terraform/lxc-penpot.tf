module "penpot" {
  source = "./modules/lxc"

  name        = "penpot"
  description = "Penpot design tool (Tailscale/LAN only)"
  vm_id       = var.lxc_vm_ids["penpot"]

  cpu_cores        = 2
  memory_dedicated = 6144
  memory_swap      = 1024
  disk_size        = 24

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["penpot"]
  ip_eth1         = local.ip_eth1["penpot"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  # Postgres data and uploaded assets are not reproducible, so this volume is included in
  # PBS backups (backup = true), unlike the default /data mounts.
  mounts = [
    { host = "/mnt/containers/lxc-penpot", mp = "/data", backup = true },
  ]
}
