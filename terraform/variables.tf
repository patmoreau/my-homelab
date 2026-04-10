variable "proxmox_endpoint" {
  type = string
}

variable "proxmox_token_id" {
  type      = string
  sensitive = false
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "pve"
}

variable "proxmox_host_ip" {
  description = "IP du host Proxmox (pour SSH provisioner)"
  type        = string
}

variable "proxmox_ssh_username" {
  type = string
}

variable "terraform_ssh_private_key" {
  type = string
}

variable "terraform_ssh_public_key" {
  type = string
}

variable "network_gateway" {
  type    = string
  default = "192.168.1.1"
}

variable "network_prefix" {
  description = "ex: 192.168.1"
  type        = string
  default     = "192.168.1"
}

variable "network_prefix_eth1" {
  description = "Network prefix for the secondary interface (vmbr1), ex: 192.168.50"
  type        = string
  default     = "192.168.50"
}

variable "dns_server" {
  type    = string
  default = "192.168.1.1"
}

variable "lxc_template" {
  type    = string
  default = "local:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
}

variable "storage_pool" {
  type    = string
  default = "local-lvm"
}

variable "lxc_vm_ids" {
  description = "VM IDs for each LXC container"
  type        = map(number)
  default = {
    gateway    = 110
    media      = 111
    essere     = 112
    monitoring = 113
    tools      = 114
    vault      = 115
    immich     = 116
  }
}

variable "lxc_ips" {
  description = "Host part of the eth0 IP, combined with network_prefix to form the full address (e.g., 40 → 192.168.8.40)"
  type        = map(number)
  default = {
    gateway    = 40
    media      = 41
    essere     = 42
    monitoring = 43
    tools      = 44
    vault      = 45
    immich     = 46
  }
}

variable "lxc_ips_eth1" {
  description = "Host part of the eth1 IP, combined with network_prefix_eth1 to form the full address (e.g., 10 → 192.168.50.10)"
  type        = map(number)
  default = {
    gateway    = 10
    media      = 11
    essere     = 12
    monitoring = 13
    tools      = 14
    vault      = 15
    immich     = 16
  }
}
