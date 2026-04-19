# LXC NFS & UID Mapping

All LXC containers run as **unprivileged** (`unprivileged: true`). NFS shares from the QNAP are mounted on the **Proxmox host** and bind-mounted into LXC containers. UID/GID mapping must be consistent between the QNAP service accounts and the LXC containers for file permissions to work.

## UID scheme

| Range  | Purpose                                                                |
| ------ | ---------------------------------------------------------------------- |
| `2000` | General media service accounts (`svc-media`)                           |
| `3000` | Sensitive service accounts (used by media Docker containers as `PUID`) |
| `100`  | Shared GID (users group on QNAP)                                       |

## 1. QNAP: create service accounts

Create the user in the QTS web UI first, then force the correct UID via SSH:

```bash
# Verify the created user
grep svc-media /etc/passwd

# Force UID to 3000
sudo sed -i 's/^svc-media:x:1003:100/svc-media:x:3000:100/' /etc/passwd

# Disable login
sudo sed -i '/^svc-media:/ s|/bin/sh|/bin/false|' /etc/passwd
sudo sed -i '/^svc-media:/ s|/share/homes/svc-media|/dev/null|' /etc/passwd

# Fix share ownership
sudo chown -R 3000:100 /share/nas-media
sudo chmod -R 770 /share/nas-media
```

## 2. Proxmox host: allow UID passthrough

Add entries to `/etc/subuid` and `/etc/subgid` on the Proxmox host so it can map the service UIDs into the containers:

```text
root:100000:65536
root:2000:1
root:3000:1
```

Apply to both `/etc/subuid` and `/etc/subgid`.

## 3. LXC container: idmap config

Terraform creates containers as unprivileged. If a container needs to access NFS shares owned by UID 3000, add the following to its `.conf` in `/etc/pve/lxc/[VMID].conf` on the Proxmox host:

```
lxc.idmap: u 0 100000 3000
lxc.idmap: u 3000 3000 1
lxc.idmap: u 3001 103001 62535
lxc.idmap: g 0 100000 100
lxc.idmap: g 100 100 1
lxc.idmap: g 101 100101 65435
```

Restart the container after editing.

## 4. Docker Compose: set PUID/PGID

NFS shares are bind-mounted into the LXC at paths like `/media/movies`. Docker containers reference those paths. Set `PUID` and `PGID` to match the QNAP service account:

```yaml
environment:
  - PUID=3000
  - PGID=100
```

These values are set per-host in Ansible:

- `lxc-media`: `nas_puid: 3000`, `nas_pgid: 100`
- All other hosts: `nas_puid: 0`, `nas_pgid: 0` (root, no NFS)

## 5. NFS mounts (Proxmox host)

NFS shares are mounted on Proxmox and bind-mounted into LXC containers via Terraform `mounts`. Example from `lxc-media.tf`:

```text
{ host = "/mnt/pve/nas-media/movies", mp = "/media/movies", ro = true }
{ host = "/mnt/pve/nas-media/downloads", mp = "/media/downloads" }
{ host = "/mnt/pve/nas-books", mp = "/media/books" }
```

The NFS mount points on Proxmox (`/mnt/pve/nas-*`) must be configured in the Proxmox UI under Datacenter → Storage.
