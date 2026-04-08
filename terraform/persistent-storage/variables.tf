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
  }))
  default = {
    "lxc-essere" = { vmid = 112, size = "5G", storage_name = "local-lvm" },
    "lxc-vault"  = { vmid = 115, size = "2G", storage_name = "local-lvm" },
  }
}
