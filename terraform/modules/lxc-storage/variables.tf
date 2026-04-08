variable "proxmox_host_ip" {
  description = "Host IP address for Proxmox (used for SSH provisioner)"
  type        = string
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
}
