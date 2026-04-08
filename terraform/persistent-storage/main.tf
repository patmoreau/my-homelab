module "persistent_storage" {
  source                    = "../modules/lxc-storage"
  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key
  storage_volumes           = var.storage_volumes
}
