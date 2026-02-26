terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "0.96.0"
    }
  }
}

provider "proxmox" {
  endpoint  = "https://homelab.lan:8006/"
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true

  ssh {
    agent    = true
    username = var.proxmox_ssh_username
  }
}
