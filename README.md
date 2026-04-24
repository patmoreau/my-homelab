# My Homelab

Infrastructure-as-code for a Proxmox-based home server. LXC containers are provisioned with **Terraform** and configured with **Ansible**.

## Repository structure

| Directory    | Purpose                                                             |
| ------------ | ------------------------------------------------------------------- |
| `terraform/` | Provisions LXC containers on Proxmox via the `bpg/proxmox` provider |
| `ansible/`   | Configures Docker services inside each LXC container                |
| `tools/`     | Custom Node.js `service-watcher` utility                            |
| `docs/`      | Supplementary setup guides (GPU passthrough, NFS UID mapping, etc.) |

## LXC containers

| Container         | Primary IP   | Services                                             |
| ----------------- | ------------ | ---------------------------------------------------- |
| lxc-gateway       | 192.168.8.40 | Traefik (reverse proxy), Cloudflare tunnel, Promtail |
| lxc-media         | 192.168.8.41 | Jellyfin, Transmission, Calibre-Web, service-watcher |
| lxc-essere        | 192.168.8.42 | WordPress / Ghost, MariaDB                           |
| lxc-monitoring    | 192.168.8.43 | Prometheus, Loki, Grafana                            |
| lxc-tools         | 192.168.8.44 | Homepage dashboard                                   |
| lxc-vault         | 192.168.8.45 | Vaultwarden (Bitwarden-compatible)                   |
| lxc-immich        | 192.168.8.46 | Immich photo management                              |
| lxc-homeassistant | 192.168.8.47 | Home automation                                      |
| lxc-pbs           | 192.168.8.48 | Proxmox Backup Server (Debian 13)                    |

## Quick start

```bash
# 1. Provision infrastructure
cd terraform
terraform init && terraform apply

# 2. Configure services
cd ansible
ansible-playbook -i inventory/hosts.yaml site.yaml
```

See [terraform/README.md](terraform/README.md) and [ansible/README.md](ansible/README.md) for full setup details.

## Networking

- Primary network: `192.168.8.x` (eth0 / vmbr0)
- Secondary network: `192.168.50.x` (eth1 / vmbr1)
- All services are exposed via Traefik under `*.homelab.lan`

## Services

The following services are configured in this homelab:

| Service             | Local Domain                                                      | Description                                                           |
| :------------------ | :---------------------------------------------------------------- | :-------------------------------------------------------------------- |
| **Traefik**         | [gateway.homelab.lan](http://gateway.homelab.lan)                 | Reverse proxy managing access to all services                         |
| **Homepage**        | [home.homelab.lan](http://home.homelab.lan)                       | Customizable dashboard for all homelab services                       |
| **Jellyfin**        | [jellyfin.homelab.lan](http://jellyfin.homelab.lan)               | Media server for movies, TV, and other media                          |
| **Calibre-Web**     | [books.homelab.lan](http://books.homelab.lan)                     | Web app for browsing and downloading eBooks                           |
| **Transmission**    | [transmission.homelab.lan](http://transmission.homelab.lan)       | BitTorrent client                                                     |
| **Filebrowser**     | [filebrowser.homelab.lan](http://filebrowser.homelab.lan)         | Web-based file manager                                                |
| **Immich**          | [immich.homelab.lan](http://immich.homelab.lan)                   | Self-hosted photo and video management                                |
| **Vaultwarden**     | [vault.moreaulab.ca](https://vault.moreaulab.ca)                  | Bitwarden-compatible password manager (exposed via Cloudflare tunnel) |
| **Grafana**         | [grafana.homelab.lan](http://grafana.homelab.lan)                 | Metrics and log dashboards (Prometheus + Loki)                        |
| **Ghost**           | [essere.homelab.lan](http://essere.homelab.lan)                   | Blog platform                                                         |
| **Service Watcher** | [service-watcher.homelab.lan](http://service-watcher.homelab.lan) | Custom Node.js utility monitoring QNAP and other services             |
| **Home Assistant**  | [ha.moreaulab.ca](https://ha.moreaulab.ca)                        | Home automation platform                                              |
| **PBS**             | [pbs.moreaulab.ca](https://pbs.moreaulab.ca)                      | Enterprise backup solution for Proxmox                                |

### Volumes & Mounts

NFS shares from the NAS are mounted on the Proxmox host under `/mnt/pve/` and bind-mounted into LXC containers via Terraform:

| Host path (Proxmox)            | Container mount point | Used by                        |
| ------------------------------ | --------------------- | ------------------------------ |
| `/mnt/pve/nas-media/downloads` | `/media/downloads`    | Transmission (read/write)      |
| `/mnt/pve/nas-media/movies`    | `/media/movies`       | Jellyfin (read-only)           |
| `/mnt/pve/nas-media/tv`        | `/media/tv`           | Jellyfin (read-only)           |
| `/mnt/pve/nas-media/kids`      | `/media/kids`         | Jellyfin (read-only)           |
| `/mnt/pve/nas-media/holidays`  | `/media/holidays`     | Jellyfin (read-only)           |
| `/mnt/pve/nas-media/les-mills` | `/media/les-mills`    | Jellyfin (read-only)           |
| `/mnt/pve/nas-books`           | `/media/books`        | Calibre-Web (read/write)       |
| `/mnt/pve/nas-photos`          | `/photos`             | Immich (read/write)            |
| `/mnt/containers/lxc-*`        | `/data`               | All LXCs (persistent app data) |
