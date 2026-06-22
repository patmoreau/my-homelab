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

variable "os_type" {
  type    = string
  default = "ubuntu"
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

variable "gpu_render_gid" {
  description = "Optional host/container GID to passthrough for the render group on unprivileged LXCs (for example 993 or 108)."
  type        = number
  default     = null

  validation {
    condition     = var.gpu_render_gid == null || var.nas_idmap == null
    error_message = "gpu_render_gid cannot be used with nas_idmap because both features define explicit gid mappings."
  }
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

variable "vlan_interfaces" {
  description = "Additional VLAN-tagged interfaces (DHCP) to attach to this container. Set mac_address to pin a static MAC so DHCP reservations survive container recreation."
  type = list(object({
    name        = string
    bridge      = string
    vlan        = number
    mac_address = optional(string)
  }))
  default = []
}

variable "nas_idmap" {
  description = "NAS UID/GID passthrough mapping. Maps a single uid:gid from the container to a specific uid:gid on the host (e.g. for NFS)."
  type = object({
    uid      = number
    gid      = number
    host_uid = optional(number)
    host_gid = optional(number)
  })
  default = null
}
