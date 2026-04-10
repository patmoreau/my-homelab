module "immich" {
  source = "./modules/lxc"

  name        = "immich"
  description = "Immich photo management"
  vm_id       = var.lxc_vm_ids["immich"]

  cpu_cores        = 6
  memory_dedicated = 8192
  memory_swap      = 1024
  disk_size        = 32

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["immich"]
  ip_eth1         = local.ip_eth1["immich"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  gpu_passthrough = true

  mounts = [
    { host = "/mnt/containers/lxc-immich", mp = "/data" },
    { host = "/mnt/pve/nas-photos", mp = "/photos" },
  ]

  nas_idmap = {
    uid = 3000
    gid = 100
  }
}
