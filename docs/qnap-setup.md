# QNAP QTS setup

## Create new shared folders

```
Control Panel
→ Shared Folders
→ Create
→ Shared Folder
```

- essere
- essere-db
- media
- gateway

## NFS Activation

Pour chaque dossier créé, il faut activer le NFS via l'interface :

```
Control Panel
→ Shared Folders
→ Sélectionner le dossier
→ Edit Shared Folder Permissions
→ NFS Host Access
→ Create
  Host/IP : 192.168.50.0/24
  Privilege: Read/Write
  Squash : All Squash (guest, guest)
```

## Mount information

```zsh
cat /etc/exports
```

## Permissions

```bash
id guest
uid=65534(guest) gid=65534(guest) groups=65534(guest)
```

```bash
sudo chown -R 65534:65534 /share/{name}
sudo chown -R 65534:65534 /share/CACHEDEV2_DATA/{name}

sudo chmod -R 777 /share/{name}
sudo chmod -R 777 /share/CACHEDEV2_DATA/{name}
```

### Verify

```bash
ls -la /share/{name}
ls -la /share/CACHEDEV2_DATA/{name}
```
