module "media" {
  source = "./modules/lxc"

  name        = "media"
  description = "Media server"
  vm_id       = var.lxc_vm_ids["media"]

  cpu_cores        = 4
  memory_dedicated = 2048
  memory_swap      = 1024
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
    { host = "/mnt/containers/lxc-media", mp = "/data" },
    # One bind mount of the whole nas-media export, not one per subdirectory. Binding the
    # subdirectories separately made each of them its own mount inside the container, so
    # rename(2) between them failed with EXDEV ("Invalid cross-device link") even though
    # they live on a single QNAP filesystem — breaking every downloads -> movies/tv/kids
    # move, in Filestash and anywhere else. Subdirectory paths are unchanged, so nothing
    # that consumes /media/<name> needs to know.
    { host = "/mnt/pve/nas-media", mp = "/media" },
    # Separate NFS export, so it stays its own mount; nests under /media to keep the path
    # stable for book-orbit. The mountpoint directory has to exist on the nas-media share.
    { host = "/mnt/pve/nas-books", mp = "/media/books" },
  ]

  nas_idmap = {
    uid = 3000
    gid = 100
  }
}
