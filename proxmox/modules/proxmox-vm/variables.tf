variable "name" {
  description = "The name of the VM"
  type        = string
}

variable "node_name" {
  description = "The Proxmox node where the VM will be placed"
  type        = string
  default     = "homelab"
}

variable "vmbr0_ipv4" {
  description = "IPv4 address and CIDR for vmbr0 (e.g. 192.168.8.50/24)"
  type        = string
}

variable "vmbr0_gw" {
  description = "IPv4 gateway for vmbr0"
  type        = string
  default     = "192.168.8.1"
}

variable "vmbr1_ipv4" {
  description = "IPv4 address and CIDR for vmbr1"
  type        = string
}

variable "vmbr1_gw" {
  description = "IPv4 gateway for vmbr1"
  type        = string
  default     = null
}

variable "ssh_public_key" {
  description = "The content of the SSH public key"
  type        = string
}

variable "proxmox_snippets_datastore" {
  description = "Proxmox datastore with snippets content type enabled"
  type        = string
  default     = "local"
}

variable "disk_datastore_id" {
  description = "Datastore ID for the VM disk"
  type        = string
  default     = "local-lvm"
}

variable "disk_size" {
  description = "Size of the VM disk in GB"
  type        = number
  default     = 20
}

variable "stop_on_destroy" {
  description = "Stop the VM on destroy"
  type        = bool
  default     = true
}

variable "vendor_data_file_name" {
  description = "Override the vendor data file name"
  type        = string
  default     = null
}

variable "image_file_name" {
  description = "Override the image file name"
  type        = string
  default     = null
}
variable "memory" {
  description = "Amount of memory in megabytes"
  type        = number
  default     = 2048
}

variable "vcpu" {
  description = "Number of vCPUs for the VM"
  type        = number
  default     = 2
}

variable "vm_user" {
  description = "The username for the VM"
  type        = string
  sensitive   = true
}
