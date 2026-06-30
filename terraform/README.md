# Terraform Setup

## Overview

Terraform provisions all LXC containers on Proxmox using the `bpg/proxmox` provider. There are two independent root modules:

| Module             | Path                            | Purpose                               |
| ------------------ | ------------------------------- | ------------------------------------- |
| Main               | `terraform/`                    | Creates all LXC containers            |
| Persistent storage | `terraform/persistent-storage/` | Creates NFS/storage mounts (run once) |

Each LXC is created via a shared `modules/lxc/` module with two network interfaces (vmbr0 + vmbr1). ID mapping internally relies on the `bpg/proxmox` provider's native `idmap` blocks to prevent Terraform state drift.

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

### 4. Ollama Phoenix iGPU prerequisites (lxc-ollama)

For Ryzen 9 8945HS / Radeon 780M (gfx1101), keep the `lxc-ollama` container unprivileged and configure the Proxmox host as follows:

- BIOS: set UMA Frame Buffer Size to `16GB` (avoid `Auto` for stable ROCm detection).
- Device permissions: ensure `/dev/kfd` and `/dev/dri/renderD128` are world-readable/writable (`0666`) via persistent udev rules.
- Render group mapping: identify host `render` GID (commonly `993` or `108`) and set `gpu_render_gid` in `terraform/lxc-ollama.tf` accordingly.

With `gpu_passthrough = true` and `gpu_render_gid` configured, the module appends:

- `lxc.mount.entry` for `/dev/kfd` and `/dev/dri`
- `lxc.idmap` gid mapping lines for the selected render gid
- matching `root:<gid>:1` entry in `/etc/subgid` on the Proxmox host

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

| Name              | VM ID | Primary IP   | Purpose                                              |
| ----------------- | ----- | ------------ | ---------------------------------------------------- |
| lxc-gateway       | 110   | 192.168.8.40 | Traefik, Cloudflare tunnel                           |
| lxc-media         | 111   | 192.168.8.41 | Jellyfin, Transmission, Book Orbit, service-watcher  |
| lxc-essere        | 112   | 192.168.8.42 | Directus, react                                      |
| lxc-monitoring    | 113   | 192.168.8.43 | Prometheus, Loki, Grafana                            |
| lxc-tools         | 114   | 192.168.8.44 | Homepage                                             |
| lxc-vault         | 115   | 192.168.8.45 | Vaultwarden                                          |
| lxc-immich        | 116   | 192.168.8.46 | Immich photo management                              |
| lxc-homeassistant | 117   | 192.168.8.47 | Home automation                                      |
| lxc-pbs           | 118   | 192.168.8.48 | Proxmox Backup Server + NAS mount (/mnt/nas-backups) |
| lxc-holefeeder    | 119   | 192.168.8.49 | Holefeeder (API, Angular, Postgres, PowerSync)       |

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

## State backups

State is stored locally (default backend) for both root modules and is **not**
committed (gitignored). [`backup-state.sh`](backup-state.sh) encrypts each state
file with [`age`](https://github.com/FiloSottile/age) and pushes the ciphertext
to the NAS via the Proxmox NFS mount (`/mnt/pve/nas-backups/terraform-state`).

Because state holds secrets, it is encrypted **before** leaving your machine — the
NAS and any downstream NAS backup only ever see `.age` ciphertext. Transport goes
through Proxmox (`terraform-admin@192.168.8.10`) with the existing
`~/.ssh/terraform_homelab` key, so it needs no NAS sk-key touch and can run
unattended.

One-time setup (no root needed — `terraform-admin` creates the NAS dir itself):

```bash
mkdir -p ~/.config/tf-state-backup && chmod 700 ~/.config/tf-state-backup
brew install age
age-keygen -o ~/.config/tf-state-backup/key.txt   # store key.txt in your password manager
# put the printed "Public key: age1..." into RECIPIENT in backup-state.sh
```

> **Key safety:** the `age` private key (`key.txt`) must live **outside** the NAS
> backup chain it protects — keep it in your password manager (primary) so a NAS
> restore that loses this machine can still decrypt. The `RECIPIENT` public key is
> safe to commit.

Run manually (keeps the newest 30 versions per state file):

```bash
cd terraform
./backup-state.sh
```

It backs up **both** root modules' state regardless of which directory you run it
from. A `terraform` wrapper function in `~/.zshrc` runs it **automatically after a
successful `apply` or `destroy`**, but only when the working directory is inside
this repo — other Terraform projects are untouched.

Restore: `age -d -i ~/.config/tf-state-backup/key.txt <file>.tfstate.age > terraform.tfstate`
