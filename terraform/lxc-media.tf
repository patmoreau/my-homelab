module "media" {
  source = "./modules/lxc"

  name        = "media"
  description = "Media server"
  vm_id       = var.lxc_vm_ids["media"]

  cpu_cores        = 4
  memory_dedicated = 2048
  memory_swap      = 512
  disk_size        = 16

  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["media"]
  hwaddr_eth0     = "bc:24:11:ae:0d:d9"
  ip_eth1         = local.ip_eth1["media"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key

  gpu_passthrough = true

  mounts = [
    { volume = "local-lvm:vm-${var.lxc_vm_ids["media"]}-media-data", mp = "/data", backup = true },
    { host = "/mnt/pve/nas-media/jellyfin", mp = "/media/jellyfin_old" },
    { host = "/mnt/pve/nas-media/downloads", mp = "/media/downloads" },
    { host = "/mnt/pve/nas-media/holidays", mp = "/media/holidays", ro = true },
    { host = "/mnt/pve/nas-media/kids", mp = "/media/kids", ro = true },
    { host = "/mnt/pve/nas-media/les-mills", mp = "/media/les-mills", ro = true },
    { host = "/mnt/pve/nas-media/movies", mp = "/media/movies", ro = true },
    { host = "/mnt/pve/nas-media/tv", mp = "/media/tv", ro = true },
    { host = "/mnt/pve/nas-books", mp = "/media/books" },
  ]

  nas_idmap = {
    uid = 3000
    gid = 100
  }
}
