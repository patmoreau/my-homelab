# GPU Passthrough for LXC Containers

## Hardware

- **GPU**: AMD Radeon Phoenix3 (integrated, PCI `c5:00.0`, device ID `1002:1900`)
- **Host kernel**: `6.17.4-2-pve` with `amdgpu` module

## Current Setup: Host-mode (amdgpu → LXC bind)

The `amdgpu` driver is loaded on the Proxmox host. It creates `/dev/dri/card0` and
`/dev/dri/renderD128`, which are bind-mounted into LXC containers via cgroup2 rules.

Docker containers inside LXC access the GPU by mounting the specific device node:

```yaml
devices:
  - /dev/dri/renderD128:/dev/dri/renderD128
group_add:
  - "993" # render group GID on this host — verify with: getent group render | cut -d: -f3
```

### LXC container config (`/etc/pve/lxc/<vmid>.conf`)

Added automatically by the `modules/lxc` Terraform module when `gpu_passthrough = true`:

```
lxc.cgroup2.devices.allow: c 226:0 rwm
lxc.cgroup2.devices.allow: c 226:128 rwm
lxc.mount.entry: /dev/dri dev/dri none bind,optional,create=dir
```

### `/etc/modprobe.d/vfio.conf` (current state)

The line that previously claimed the GPU for VFIO has been removed. The file is now empty
(or contains only unrelated options):

```
# vfio-pci ids=1002:1900 line was removed on 2026-04-10
# to allow amdgpu to bind instead — see docs/gpu-passthrough-lxc.md
```

---

## Reverting to VM Passthrough (vfio-pci)

If you ever need to pass the GPU to a VM exclusively (e.g. a Windows or gaming VM),
follow these steps:

### 1. Stop any LXC containers using the GPU

```bash
ssh -i ~/.ssh/terraform_homelab terraform-admin@192.168.8.10 \
  "sudo /usr/sbin/pct stop 116"  # lxc-immich
```

### 2. Re-enable vfio-pci binding

```bash
ssh -i ~/.ssh/terraform_homelab terraform-admin@192.168.8.10 "
  echo 'options vfio-pci ids=1002:1900 disable_vga=1' \
    | sudo tee /etc/modprobe.d/vfio.conf
  sudo update-initramfs -u -k all
"
```

### 3. Reboot Proxmox host

After reboot, `vfio-pci` will claim the GPU and `/dev/dri` will no longer exist on the host.

### 4. Disable GPU in Immich docker-compose

Remove the `devices` and `group_add` and `environment` GPU entries from
`ansible/roles/immich/templates/docker-compose.yaml.j2`, then run:

```bash
cd ansible && ansible-playbook -i inventory/hosts.yaml site.yaml --limit lxc-immich
```

### 5. Add `hostpci` to the VM Terraform config

```hcl
dynamic "hostpci" {
  for_each = var.hostpci != null ? [var.hostpci] : []
  content {
    device  = "hostpci0"
    mapping = hostpci.value.mapping
    pcie    = hostpci.value.pcie
    rombar  = hostpci.value.rombar
    xvga    = hostpci.value.xvga
  }
}
```

---

## Notes

- `firmware-amd-graphics` from Debian `non-free-firmware` **cannot** be installed alongside
  `pve-firmware` (they conflict). The Proxmox-bundled firmware (`pve-firmware`) already
  includes Phoenix3 firmware files (`gc_11_5_*.bin`, `dcn_3_1_*.bin`) — no extra package needed.
- The render group GID on this host is **993**. If it changes after a reinstall, update
  `group_add` in the Immich docker-compose template.
- LXC containers are **unprivileged** — the `/dev/dri` devices appear as owned by
  `nobody:nogroup` inside the container, but are accessible via the `render` group.
