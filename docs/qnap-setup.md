# QNAP Setup

One-time configuration on the QNAP. For UID mapping and NFS permissions on the Proxmox/LXC side, see [lxc_nfs_uid_mapping.md](lxc_nfs_uid_mapping.md).

## 1. Shared folders

Create the following shared folders in **Control Panel → Shared Folders → Create**:

| Folder      | Purpose                               |
| ----------- | ------------------------------------- |
| `nas-media` | Jellyfin, Transmission, Calibre media |
| `nas-books` | Calibre book library                  |

## 2. NFS access

For each folder, enable NFS in **Control Panel → Shared Folders → Edit → NFS Host Access**:

- **Host/IP:** `192.168.50.0/24` (Proxmox vmbr1 network)
- **Privilege:** Read/Write
- **Squash:** All Squash (maps all access to `svc-media`)

Verify exports are active:

```bash
cat /etc/exports
```

## 3. Service accounts

Create service accounts in the QTS web UI, then lock them down via SSH. See [lxc_nfs_uid_mapping.md](lxc_nfs_uid_mapping.md) for the UID forcing and ownership steps.

| Account     | UID    | Used by                         |
| ----------- | ------ | ------------------------------- |
| `svc-media` | `3000` | Jellyfin, Transmission, Calibre |

## 4. service-watcher SSH key

The service-watcher on `lxc-media` SSHes into the QNAP to monitor RAID status. It uses a restricted key that can only run the mdstat check command.

Add the following to `~/.ssh/authorized_keys` on the QNAP (replace `YOUR_PUB_KEY` with the content of `id_ed25519_qnap_monitor.pub`):

```
command="if grep -qE 'check|resync|repair|recovery|reshape' /proc/mdstat; then grep -E 'check|resync|repair|recovery|reshape' /proc/mdstat; else echo 'IDLE'; fi",no-port-forwarding,no-x11-forwarding,no-agent-forwarding YOUR_PUB_KEY
```

> Enable **Home Service** in Control Panel so `~/.ssh/authorized_keys` persists across reboots.

Verify the key works:

```bash
ssh -i ~/.ssh/id_ed25519_qnap_monitor homelab_user@qnap.homelab.lan
```
