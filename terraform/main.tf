terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_endpoint
  api_token = "${var.proxmox_token_id}=${var.proxmox_token_secret}"
  insecure  = true

  ssh {
    agent       = false
    username    = var.proxmox_ssh_username
    private_key = file(pathexpand(var.terraform_ssh_private_key))
  }
}

locals {
  ssh_public_key = trimspace(file(pathexpand(var.terraform_ssh_public_key)))

  # Helper pour construire les IPs
  # lxc_ips["gateway"] = 40 → "192.168.8.40/24"
  ip = {
    for name, last_octet in var.lxc_ips :
    name => "${var.network_prefix}.${last_octet}"
  }

  ip_eth1 = {
    for name, last_octet in var.lxc_ips_eth1 :
    name => "${var.network_prefix_eth1}.${last_octet}"
  }
}
