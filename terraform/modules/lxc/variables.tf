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
  default = 4
}

variable "mounts" {
  description = "Bind mounts or Proxmox storage volume mounts applied via pct set. Use 'host' for bind mounts, 'volume' for an existing Proxmox volid (e.g. from module.lxc_volume.volids)."
  type = list(object({
    host   = optional(string)
    volume = optional(string)
    mp     = string
    ro     = optional(bool, false)
    backup = optional(bool, false)
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

variable "hwaddr_eth0" {
  description = "Optional MAC address for eth0 (ip_eth0)"
  type        = string
  default     = null
}

variable "nas_idmap" {
  description = "NAS UID/GID passthrough mapping. Maps a single uid:gid from the NAS directly into the unprivileged container so bind-mounted NAS shares have correct ownership."
  type = object({
    uid = number
    gid = number
  })
  default = null
}
