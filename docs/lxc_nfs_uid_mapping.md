# Proxmox LXC & QNAP NFS: UID Mapping Guide

This guide is to segregate service accounts by type of content and settings their permissions. Those will be mapped to Proxmox users.

- Normal service account will use the UID 2000 range.
- Sensitive service account will use the UID 3000 range.

## 1. QNAP Setup (Service Accounts)

Avoid using personal accounts. Create dedicated Service Accounts via SSH on your QNAP (QTS).

- svc-media

### Create Service Users

Create the users in the QTS Web UI first, then force the UIDs via SSH:

### Verify service user

```bash
grep svc-media /etc/passwd
```

### Force change UID

```bash
sudo sed -i 's/^svc-media:x:1003:100/svc-media:x:3000:100/' /etc/passwd
```

### Prevent logging on

```bash
sudo sed -i '/^svc-media:/ s|/bin/sh|/bin/false|' /etc/passwd
```

### No home directory

```bash
sudo sed -i '/^svc-media:/ s|/share/homes/svc-media|/dev/null|' /etc/passwd
```

### Fix Ownership on the NAS shares

```bash
sudo chown -R 3000:100 /share/vault
sudo chown -R 3000:100 /share/CACHEDEV2_DATA/vault
sudo chmod -R 770 /share/vault
sudo chmod -R 770 /share/CACHEDEV2_DATA/vault
```

---

## 2. Proxmox Host Configuration

Proxmox must be authorized to map the host's UIDs (2000, 3000).

### Edit Sub-IDs (/etc/subuid and /etc/subgid)

root:100000:65536
root:2000:1
root:3000:1

---

## 3. LXC Container Mapping (.conf)

Location: /etc/pve/lxc/[ID].conf

### Configuration for General Services (UID 2000)

unprivileged: 1
lxc.idmap: u 0 100000 2000
lxc.idmap: u 2000 2000 1
lxc.idmap: u 2001 102001 63535
lxc.idmap: g 0 100000 100
lxc.idmap: g 100 100 1
lxc.idmap: g 101 100101 65435

### Configuration for Vaultwarden (UID 3000)

unprivileged: 1
lxc.idmap: u 0 100000 3000
lxc.idmap: u 3000 3000 1
lxc.idmap: u 3001 103001 62535
lxc.idmap: g 0 100000 100
lxc.idmap: g 100 100 1
lxc.idmap: g 101 100101 65435

---

## 4. Docker Compose Integration

Example for Vaultwarden:

```docker-compose.yml

services:
  vaultwarden:
    image: vaultwarden/server:latest
    user: "3000:100"
    environment:
      - PUID=3000
      - PGID=100
    volumes:
      - /mnt/nfs/vaultwarden:/data
```
