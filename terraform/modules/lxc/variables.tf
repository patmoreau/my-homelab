variable "name" {
  type = string
}

variable "description" {
  type = string
}

variable "vm_id" {
  type = number
}

variable "proxmox_node" {
  type = string
}

variable "dns_server" {
  type = string
}

variable "ip_eth0" {
  type = string
}

variable "ip_eth1" {
  type = string
}

variable "network_gateway" {
  type = string
}

variable "ssh_public_key" {
  type = string
}

variable "lxc_template" {
  type = string
}

variable "storage_pool" {
  type = string
}

variable "cpu_cores" {
  type    = number
  default = 2
}

variable "memory_dedicated" {
  type    = number
  default = 512
}

variable "memory_swap" {
  type    = number
  default = 256
}

variable "disk_size" {
  type    = number
  default = 8
}

variable "mounts" {
  description = "Bind mounts applied via pct set on the Proxmox host"
  type = list(object({
    host = string
    mp   = string
    ro   = optional(bool, false)
  }))
  default = []
}

variable "gpu_passthrough" {
  description = "Enable Intel/AMD GPU passthrough (adds cgroup2 and /dev/dri mount entries)"
  type        = bool
  default     = false
}

variable "proxmox_host_ip" {
  type = string
}

variable "proxmox_ssh_username" {
  type = string
}

variable "terraform_ssh_private_key" {
  type = string
}
