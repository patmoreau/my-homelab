# Proxmox Host Setup (pve-homelab)

Reference inventory of the **manual configuration** on the physical Proxmox host,
captured to drive codification into the `ansible/proxmox.yaml` lane (the host-level
Ansible lane, separate from `site.yaml` which configures the LXCs).

> **Status:** captured 2026-07-19 from the live host + existing `docs/`. Nothing here is
> automated yet except NUT. This is the roadmap for building the `pve_*` roles.

## Host facts

| Item        | Value                                             |
| ----------- | ------------------------------------------------- |
| Hostname/IP | `homelab` / `192.168.8.10` (mgmt on vmbr0)        |
| PVE version | `pve-manager/9.1.4`                               |
| Kernel      | `6.17.4-2-pve`                                     |
| OS          | Debian 13 (trixie)                                |
| CPU/IOMMU   | AMD, `amd_iommu=on iommu=pt` (see GRUB below)      |
| Root disk   | LVM: `pve/root` (ext4), `pve/swap`, `local-lvm` (lvmthin `pve/data`) |
| GPU         | AMD Radeon Phoenix3, amdgpu host-mode → see `docs/gpu-passthrough-lxc.md` |

## Ansible connection

The host is reached as **`terraform-admin`** (passwordless sudo) with the
`~/.ssh/terraform_homelab` key + `become: true` — set via `ansible_user` on
`pve-homelab` in `inventory/hosts.yaml`. Root SSH is **not** permitted.

## Codification roadmap

Status: **6 of 7 roles built & applied** (2026-07-20). Only `pve_api_access` remains.

| # | Area | Role | Status |
| - | ---- | ---- | ------ |
| 1 | APT no-subscription repo | `pve_repos` | ✅ built + applied |
| 2 | `terraform-admin` user + sudoers + keys | `pve_admin` | ✅ built + applied (sudoers consolidated) |
| 3 | PVE API users/roles/tokens | `pve_api_access` | ⏳ **pending** — ACL captured below |
| 4 | NFS storage (pvesm) | `pve_storage` | ✅ built + applied (idempotent) |
| 5 | subuid / subgid (NAS + GPU idmap) | `pve_nas_idmap` | ✅ built + applied |
| 6 | ZFS ARC limit | `pve_tuning` | ✅ built + applied |
| 7 | Timezone / NTP | `pve_tuning` | ✅ built + applied |
| 8 | Network (`/etc/network/interfaces`) | ❌ leave manual | — (`docs/iot-vlan-network.md`) |
| 9 | GRUB / IOMMU / VFIO modules | ❌ leave manual | — (`docs/gpu-passthrough-lxc.md`) |

Rationale for leaving #8/#9 manual: PVE owns `/etc/network/interfaces`, and both the
network and bootloader require reboots and can **lock you out of the host** (needing
console/physical access) if a change is wrong. They stay documented, not automated.

---

## 1. APT repositories

`/etc/apt/sources.list` + `/etc/apt/sources.list.d/` (deb822 format):

```text
# Debian
deb http://deb.debian.org/debian trixie          main contrib non-free-firmware
deb http://deb.debian.org/debian trixie-updates   main contrib non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free-firmware
# Proxmox
deb http://download.proxmox.com/debian/pve trixie pve-no-subscription
```

- Enterprise repo removed, **no-subscription** repo added (standard homelab post-install).
- Subscription nag is **NOT** patched — left as-is intentionally. No action.

## 2. Admin user & sudo

| User              | UID  | Shell       | Notes                          |
| ----------------- | ---- | ----------- | ------------------------------ |
| `root`            | 0    | `/bin/bash` |                                |
| `pmoreau`         | 1000 | `/bin/bash` | personal login                 |
| `terraform-admin` | 1001 | `/bin/sh`   | automation account (TF + Ansible) |

**⚠️ Sudoers conflict to fix during codification** — two files exist:

```text
/etc/sudoers.d/terraform         → terraform-admin ALL=(ALL) NOPASSWD:ALL     (this one wins)
/etc/sudoers.d/terraform-admin   → terraform-admin ALL=(ALL) NOPASSWD: /usr/sbin/pct, /usr/bin/tee, /usr/bin/sed  (dead)
```

`pve_admin` should own **one** canonical sudoers file and remove the other.

SSH keys present (public, by comment):
- `root`: `patrick@drifterapps.com` (sk-ed25519), an ed25519, `root@homelab` (rsa), `terraform-homelab`
- `terraform-admin`: the shared ed25519 + `terraform-homelab`

## 3. PVE API access

`pveum` objects (realms `pam` + `pve` are stock):

| User                  | Purpose                                   |
| --------------------- | ----------------------------------------- |
| `terraform-user@pve`  | Terraform API user (creates/manages LXCs) |
| `api@pam`             | monitoring; owns token `api@pam!homepage` |
| `pmoreau@pam`, `root@pam`, `terraform-admin@pam` | logins |

Token: **`api@pam!homepage`** (privsep=1) — used by homepage widget / `pve_exporter`
(matches `vault_pve_token_id` / `vault_pve_token_secret`).

> **⚠️ Token caveat:** PVE reveals a token secret **only at creation time**. The
> `pve_api_access` role can ensure the user/role/ACL exist and create a token **only if
> absent**, but cannot reconcile an existing secret. Rotating a token means updating the
> vault. Build this role create-if-missing.

### Captured ACL (2026-07-20) — to reproduce in `pve_api_access`

`pveum acl list`:

| Path | Role | Grantee |
| ---- | ---- | ------- |
| `/` | `Administrator` | user `terraform-user@pve` |
| `/` | `PVEAdmin` | token `terraform-user@pve!token-id` |
| `/nodes/homelab` | `PVEAdmin` | token `!token-id` |
| `/storage/local` | `PVEAdmin` | token `!token-id` |
| `/storage/local-lvm` | `PVEAdmin` | token `!token-id` |
| `/mapping/pci/gpu` | `PVEMappingUser` | token `!token-id` (GPU passthrough mapping) |
| `/` | `PVEAuditor` | token `api@pam!homepage` + group `api-ro-users` |
| `/nodes/homelab`, `/storage/local` | `Administrator` | user `terraform-admin@pam` |

Token `terraform-user@pve!token-id` is **privsep=0** — so it inherits the user's full
`Administrator` at `/`, making the per-path token ACLs effectively redundant. Reproduce
as-is for fidelity; a future tightening pass could switch to `privsep=1` with the scoped
roles above. Also present: group `api-ro-users` (PVEAuditor). Roles used are all
**built-in** PVE roles (no custom roles) — nothing extra to define.

## 4. NFS storage

`/etc/pve/storage.cfg` — 4 NFS stores from the NAS (`192.168.50.1`, over the vmbr1 direct link):

| Storage       | Export     | Mountpoint            | Content |
| ------------- | ---------- | --------------------- | ------- |
| `nas-books`   | `/books`   | `/mnt/pve/nas-books`  | rootdir |
| `nas-media`   | `/media`   | `/mnt/pve/nas-media`  | rootdir |
| `nas-photos`  | `/photos`  | `/mnt/pve/nas-photos` | rootdir |
| `nas-backups` | `/backups` | `/mnt/pve/nas-backups`| rootdir |

Plus stock `local` (dir) and `local-lvm` (lvmthin). Codify the NFS stores via
`pvesm add nfs ...` (idempotent). See also `docs/lxc_nfs_uid_mapping.md`.

## 5. subuid / subgid (unprivileged LXC idmap)

Custom entries beyond the adduser-generated ranges (`*:100000:65536`, per-user ranges):

```text
# /etc/subuid
root:3000:1        # svc-media / sensitive service UID
root:3001:1        # svc-backup (PBS) UID

# /etc/subgid
root:100:1         # QNAP "users" group
root:993:1         # render group (GPU passthrough into LXC)
root:3001:1        # svc-backup GID
```

**⚠️ Doc drift:** `docs/lxc_nfs_uid_mapping.md` lists `root:2000:1`; the live host uses
`3000`/`3001` and adds `993` (render). Reconcile the doc when building `pve_nas_idmap`.

## 6. ZFS tuning

`/etc/modprobe.d/zfs.conf`:

```text
options zfs zfs_arc_max=6508511232   # ~6 GiB ARC cap
```

(Main storage is LVM-thin; ZFS present but ARC capped so it doesn't eat host RAM.)

## 7. Timezone / NTP

`America/Montreal`, `chrony` active, clock synchronized. Trivial to codify; low value.

## 8. Network — **leave manual** (documented)

`/etc/network/interfaces` (PVE-managed, "do not edit directly"):

```text
vmbr0  192.168.8.10/24  gw 192.168.8.1   bridge-ports nic0   bridge-vlan-aware yes   bridge-vids 2-4094
vmbr1  192.168.50.2/24                    bridge-ports nic1
```

- vmbr0 is **VLAN-aware** (carries VLAN 10 IoT) — full procedure in `docs/iot-vlan-network.md`.
- vmbr1 is the direct NAS link (`192.168.50.x`), where NFS is served.
- Do **not** automate this file — lockout risk.

## 9. GRUB / IOMMU / VFIO — **leave manual** (documented)

```text
/etc/default/grub   GRUB_CMDLINE_LINUX_DEFAULT="quiet amd_iommu=on iommu=pt"
/etc/modules        vfio  vfio_iommu_type1  vfio_pci
/etc/modprobe.d/vfio.conf   (empty — GPU intentionally NOT claimed by vfio)
```

**⚠️ Stale cruft:** the `vfio*` modules in `/etc/modules` are leftovers from the earlier
VFIO-passthrough era. The GPU now runs **amdgpu host-mode** (empty `vfio.conf`, render GID
993, `/dev/dri` present) — see `docs/gpu-passthrough-lxc.md`. These modules load but bind
nothing; harmless, but candidates for cleanup (requires `update-initramfs` + reboot).

---

## Known issues to fix during codification

1. ✅ **Sudoers conflict** (#2) — DONE: `pve_admin` now owns one `NOPASSWD:ALL` file; legacy `/etc/sudoers.d/terraform` removed.
2. ✅ **subuid/subgid doc drift** (#5) — DONE: `pve_nas_idmap` codifies 3000/3001 + 993; `docs/lxc_nfs_uid_mapping.md` reconciled.
3. ⏳ **VFIO leftovers** (#9) — `/etc/modules` loads unused vfio modules (still open; cleanup needs reboot).
4. ⏳ **API token rotation** (#3) — for `pve_api_access`: create-if-missing only; document rotation → vault flow.
5. ✅ **Capture `terraform-user@pve` ACL** (#3) — DONE: captured in section 3 above.

## Related docs

- `docs/iot-vlan-network.md` — VLAN 10 IoT trunk (network)
- `docs/gpu-passthrough-lxc.md` — GPU / amdgpu host-mode
- `docs/lxc_nfs_uid_mapping.md` — NFS + UID mapping detail
- `docs/qnap-setup.md` — NAS side
- `ansible/README.md` → "Hypervisor playbook" — the `proxmox.yaml` lane + `nut_server`
