variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_host_ip" {
  description = "Host IP address for Proxmox (used for SSH provisioner)"
  type        = string
}

variable "proxmox_token_id" {
  type      = string
  sensitive = false
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_username" {
  type = string
}

variable "terraform_ssh_private_key" {
  type = string
}

variable "storage_volumes" {
  type = map(object({
    vmid         = number
    size         = string
    storage_name = string
    disk_name    = string
  }))
  default = {
    "lxc-media"         = { vmid = 111, size = "10G", storage_name = "local-lvm", disk_name = "media-data" },
    "lxc-essere"        = { vmid = 112, size = "10G", storage_name = "local-lvm", disk_name = "essere-data" },
    "lxc-monitoring"    = { vmid = 113, size = "8G", storage_name = "local-lvm", disk_name = "monitoring-data" },
    "lxc-vault"         = { vmid = 115, size = "2G", storage_name = "local-lvm", disk_name = "vault-data" },
    "lxc-immich"        = { vmid = 116, size = "25G", storage_name = "local-lvm", disk_name = "immich-data" },
    "lxc-homeassistant" = { vmid = 117, size = "10G", storage_name = "local-lvm", disk_name = "homeassistant-data" },
    "lxc-holefeeder"    = { vmid = 119, size = "20G", storage_name = "local-lvm", disk_name = "holefeeder-data" },
  }
}
