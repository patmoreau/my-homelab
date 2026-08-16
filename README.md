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

| Container         | Primary IP   | Services                                                     |
| ----------------- | ------------ | ------------------------------------------------------------ |
| lxc-gateway       | 192.168.8.40 | Traefik (reverse proxy), Cloudflare tunnel, Promtail         |
| lxc-media         | 192.168.8.41 | Jellyfin, Transmission, Book orbit, service-watcher          |
| lxc-essere        | 192.168.8.42 | Directus, React, postgres                                    |
| lxc-monitoring    | 192.168.8.43 | Prometheus, Loki, Grafana                                    |
| lxc-tools         | 192.168.8.44 | Homepage dashboard                                           |
| lxc-vault         | 192.168.8.45 | Vaultwarden (Bitwarden-compatible)                           |
| lxc-immich        | 192.168.8.46 | Immich photo management                                      |
| lxc-homeassistant | 192.168.8.47 | Home automation (eth2: IoT network 192.168.10.x via VLAN 10) |
| lxc-pbs           | 192.168.8.48 | Proxmox Backup Server (Debian 13)                            |

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

Routing is handled by a Flint 2 router (GL-MT6000)

- Primary network: `192.168.8.x` (Morindin_BlackTower)

  - WAN/LAN1 (2500 Mbps): pve (eth0 / vmbr0) — also carries VLAN 10 trunk to IoT network
  - LAN2 (): Apple TV
  - LAN3 (): Honeywell Gateway
  - LAN4 (): nas port 1
  - LAN5 (): nas port 2

- Guest network: `192.168.9.x` (Morindin_WhiteTower)
- IoT network: `192.168.10.x` (Morindin_GhenjeiTower)
- Direct network: `192.168.50.x`

  - pve (eth1 / vmbr1)
  - nas port 5

- All services are exposed via Traefik under `*.moreaulab.ca`
- `*.homelab.lan` is local DNS for direct host access (SSH, Proxmox API on `:8006`) that
  bypasses Traefik

### IoT VLAN trunk

The IoT network (`192.168.10.x`, VLAN 10) is trunked from the Flint 2 to the Proxmox host over the main LAN cable (Proxmox has no free NIC), then attached to LXC containers as `eth2`. This lets `lxc-homeassistant` reach IoT devices while keeping them isolated from the main LAN.

Full replication runbook — router trunk, Proxmox VLAN config, Terraform interface, and the proxy-ARP/firewall rules that let Home Assistant talk to isolated IoT devices — is in [docs/iot-vlan-network.md](docs/iot-vlan-network.md).

LXC containers that need IoT access set the `vlan_interfaces` parameter in their `terraform/lxc-<name>.tf`:

```hcl
vlan_interfaces = [
  { name = "eth2", bridge = "vmbr0", vlan = 10 }
]
```

## Services

The following services are configured in this homelab:

| Service             | Domain                                                               | Description                                                           |
| :------------------ | :------------------------------------------------------------------- | :-------------------------------------------------------------------- |
| **Traefik**         | [gateway.moreaulab.ca](https://gateway.moreaulab.ca)                 | Reverse proxy managing access to all services                         |
| **Homepage**        | [home.moreaulab.ca](https://home.moreaulab.ca)                       | Customizable dashboard for all homelab services                       |
| **Jellyfin**        | [jellyfin.moreaulab.ca](https://jellyfin.moreaulab.ca)               | Media server for movies, TV, and other media                          |
| **Book Orbit**      | [books.moreaulab.ca](https://books.moreaulab.ca)                     | Web app for browsing and downloading eBooks                           |
| **Transmission**    | [transmission.moreaulab.ca](https://transmission.moreaulab.ca)       | BitTorrent client                                                     |
| **Filebrowser**     | [filebrowser.moreaulab.ca](https://filebrowser.moreaulab.ca)         | Web-based file manager                                                |
| **Immich**          | [immich.moreaulab.ca](https://immich.moreaulab.ca)                   | Self-hosted photo and video management                                |
| **Vaultwarden**     | [vault.moreaulab.ca](https://vault.moreaulab.ca)                     | Bitwarden-compatible password manager (exposed via Cloudflare tunnel) |
| **Grafana**         | [grafana.moreaulab.ca](https://grafana.moreaulab.ca)                 | Metrics and log dashboards (Prometheus + Loki)                        |
| **Prometheus**      | [prometheus.moreaulab.ca](https://prometheus.moreaulab.ca)           | Metrics collection and alerting                                       |
| **Essere**          | [essere.ca](https://essere.ca)                                       | Public site + Directus CMS (`admin.essere.ca`)                        |
| **Umami**           | [analytics.moreaulab.ca](https://analytics.moreaulab.ca)             | Cookieless web analytics for essere.ca                                |
| **Service Watcher** | [service-watcher.moreaulab.ca](https://service-watcher.moreaulab.ca) | Custom Node.js utility monitoring QNAP and other services             |
| **NAS**             | [nas.moreaulab.ca](https://nas.moreaulab.ca)                         | QNAP NAS web UI                                                       |
| **Proxmox VE**      | [pve.moreaulab.ca](https://pve.moreaulab.ca)                         | Hypervisor web UI                                                     |
| **Router**          | [router.moreaulab.ca](https://router.moreaulab.ca)                   | GL.iNet Flint 2 panel (LuCI on `:8443`)                               |
| **Home Assistant**  | [ha.moreaulab.ca](https://ha.moreaulab.ca)                           | Home automation platform                                              |
| **PBS**             | [pbs.moreaulab.ca](https://pbs.moreaulab.ca)                         | Enterprise backup solution for Proxmox                                |

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
| `/mnt/pve/nas-books`           | `/media/books`        | Book Orbit (read/write)        |
| `/mnt/pve/nas-photos`          | `/photos`             | Immich (read/write)            |
| `/mnt/containers/lxc-*`        | `/data`               | All LXCs (persistent app data) |
