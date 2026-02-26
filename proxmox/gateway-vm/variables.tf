variable "proxmox_token_id" {
  type      = string
  sensitive = false
}

variable "proxmox_token_secret" {
  type      = string
  sensitive = true
}

variable "proxmox_ssh_username" {
  type        = string
  description = "SSH username for the Proxmox host (used to upload snippets)"
  default     = "root"
}

variable "proxmox_snippets_datastore" {
  type        = string
  description = "Proxmox datastore with snippets content type enabled"
  default     = "local"
}

variable "name" {
  description = "The name of the VM"
  type        = string
}

variable "node_name" {
  description = "The Proxmox node to deploy the VM to"
  type        = string
  default     = "homelab"
}

variable "vmbr0_ipv4" {
  description = "IPv4 address for vmbr0 (e.g. 192.168.8.50/24)"
  type        = string
}

variable "vmbr0_gw" {
  description = "IPv4 gateway for vmbr0"
  type        = string
  default     = "192.168.8.1"
}
variable "memory" {
  description = "Amount of memory in megabytes for the VM"
  type        = number
  default     = 2048
}

variable "vcpu" {
  description = "Number of vCPUs for the VM"
  type        = number
  default     = 2
}

variable "disk_size" {
  description = "Size of the VM disk in GB"
  type        = number
  default     = 20
}

variable "vmbr1_ipv4" {
  description = "IPv4 address for vmbr1"
  type        = string
}

variable "vmbr1_gw" {
  description = "IPv4 gateway for vmbr1 (optional)"
  type        = string
  default     = null
}
