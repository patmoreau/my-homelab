# Terraform Setup

## Overview

Terraform provisions all LXC containers on Proxmox using the `bpg/proxmox` provider. There are two independent root modules:

| Module             | Path                            | Purpose                               |
| ------------------ | ------------------------------- | ------------------------------------- |
| Main               | `terraform/`                    | Creates all LXC containers            |
| Persistent storage | `terraform/persistent-storage/` | Creates NFS/storage mounts (run once) |

Each LXC is created via a shared `modules/lxc/` module with two network interfaces (vmbr0 + vmbr1).

## Proxmox prerequisites

### 1. Create the `terraform-admin` SSH user on Proxmox

```bash
useradd -m -s /bin/bash terraform-admin
echo 'terraform-admin ALL=(ALL) NOPASSWD: /usr/sbin/pct, /usr/bin/tee' > /etc/sudoers.d/terraform-admin
```

### 2. Create a Proxmox API token

In the Proxmox UI: Datacenter → Permissions → API Tokens → Add

- User: `terraform-user@pve`
- Token ID: `token-id`
- Uncheck "Privilege Separation"

Grant it `Administrator` role on `/`.

### 3. Generate the Terraform SSH key (on your machine)

```bash
ssh-keygen -t ed25519 -C "terraform-homelab" -f ~/.ssh/terraform_homelab -N ""
chmod 600 ~/.ssh/terraform_homelab
```

Copy the public key to Proxmox:

```bash
ssh-copy-id -i ~/.ssh/terraform_homelab.pub terraform-admin@proxmox.homelab.lan
```

Add to `~/.ssh/config` for convenience:

```
Host proxmox
  HostName proxmox.homelab.lan
  User terraform-admin
  IdentityFile ~/.ssh/terraform_homelab
  IdentitiesOnly yes
```

## terraform.tfvars

Both modules need a `terraform.tfvars`. Key values to set:

| Variable                    | Description                                              |
| --------------------------- | -------------------------------------------------------- |
| `proxmox_endpoint`          | Proxmox API URL, e.g. `https://proxmox.homelab.lan:8006` |
| `proxmox_token_id`          | API token, e.g. `terraform-user@pve!token-id`            |
| `proxmox_token_secret`      | API token secret (UUID)                                  |
| `proxmox_node`              | Proxmox node name (e.g. `homelab`)                       |
| `proxmox_host_ip`           | Proxmox host IP for SSH provisioner                      |
| `proxmox_ssh_username`      | `terraform-admin`                                        |
| `terraform_ssh_private_key` | `~/.ssh/terraform_homelab`                               |
| `terraform_ssh_public_key`  | `~/.ssh/terraform_homelab.pub`                           |
| `network_gateway`           | LAN gateway, e.g. `192.168.8.1`                          |
| `network_prefix`            | Primary network prefix, e.g. `192.168.8`                 |
| `network_prefix_eth1`       | Secondary network prefix, e.g. `192.168.50`              |
| `dns_server`                | DNS server IP                                            |
| `lxc_template`              | Proxmox template path for Ubuntu 24.04                   |
| `storage_pool`              | Proxmox storage pool, e.g. `local-lvm`                   |

## LXC containers

| Name           | VM ID | Primary IP   | Purpose                                          |
| -------------- | ----- | ------------ | ------------------------------------------------ |
| lxc-gateway    | 110   | 192.168.8.40 | Traefik, Cloudflare tunnel                       |
| lxc-media      | 111   | 192.168.8.41 | Jellyfin, Transmission, Calibre, service-watcher |
| lxc-essere     | 112   | 192.168.8.42 | WordPress, Ghost                                 |
| lxc-monitoring | 113   | 192.168.8.43 | Prometheus, Loki, Grafana                        |
| lxc-tools      | 114   | 192.168.8.44 | Homepage                                         |
| lxc-vault      | 115   | 192.168.8.45 | Vaultwarden                                      |

## Workflow

```bash
cd terraform

# First time
terraform init
terraform plan
terraform apply

# Destroy and recreate a single resource
terraform destroy -target=module.media
terraform apply -target=module.media
```

For persistent storage (run once, rarely changed):

```bash
cd terraform/persistent-storage
terraform init
terraform apply
```
