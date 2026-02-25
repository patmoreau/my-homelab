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
