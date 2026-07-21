---
description: "Use when creating a new LXC container, removing a container, adding NFS mounts or GPU passthrough, modifying Terraform variables, changing IP addresses or VM IDs, or working with Proxmox infrastructure. Includes the full checklist for new containers and the README update requirement."
applyTo: "terraform/**"
---

# Terraform — LXC Container Instructions

## README Update Rule

> See the canonical [README Update Rule](../../AGENTS.md#readme-update-rule-always-apply).
> For Terraform: update `terraform/README.md` when adding or removing a container, or
> changing a Terraform variable or module.

## Creating a New LXC Container

Work through every step in order. Do not skip any step.

### Step 1 — Create `terraform/lxc-<name>.tf`

Use the shared `modules/lxc` module:

```hcl
module "<name>" {
  source = "./modules/lxc"

  name        = "<name>"
  description = "<human-readable description>"
  vm_id       = var.lxc_vm_ids["<name>"]

  # Resources — adjust to workload
  cpu_cores        = 2
  memory_dedicated = 512    # MiB
  memory_swap      = 256    # MiB
  disk_size        = 4      # GiB

  # Infrastructure — always use these locals/vars
  proxmox_node    = var.proxmox_node
  dns_server      = var.dns_server
  ip_eth0         = local.ip["<name>"]
  ip_eth1         = local.ip_eth1["<name>"]
  network_gateway = var.network_gateway
  ssh_public_key  = local.ssh_public_key
  lxc_template    = var.lxc_template
  storage_pool    = var.storage_pool

  proxmox_host_ip           = var.proxmox_host_ip
  proxmox_ssh_username      = var.proxmox_ssh_username
  terraform_ssh_private_key = var.terraform_ssh_private_key
}
```

**Optional parameters** (add only when needed):

| Parameter         | Type     | When to use                                        |
| ----------------- | -------- | -------------------------------------------------- |
| `hwaddr_eth0`     | `string` | Pin a static MAC address for eth0                  |
| `gpu_passthrough` | `bool`   | Intel/AMD GPU access (e.g. Jellyfin transcoding)   |
| `mounts`          | `list`   | NFS bind mounts or Proxmox storage volumes         |
| `nas_idmap`       | `object` | UID/GID mapping for NAS bind mounts (`uid`, `gid`) |

### Step 2 — Update `terraform/variables.tf`

Add `<name>` to **three** maps (pick the next sequential values):

```hcl
variable "lxc_vm_ids" {
  default = {
    # existing entries ...
    <name> = <next_vm_id>     # current max is 115; use 116, 117, ...
  }
}

variable "lxc_ips" {
  default = {
    # existing entries ...
    <name> = <octet>          # current max is 45; use 46, 47, ...
  }
}

variable "lxc_ips_eth1" {
  default = {
    # existing entries ...
    <name> = <octet>          # current max is 15; use 16, 17, ...
  }
}
```

### Step 3 — Update `terraform/outputs.tf`

Add `<name>` to both output blocks:

```hcl
output "lxc_ips" {
  value = {
    # existing ...
    <name> = module.<name>.ip
  }
}

output "lxc_ids" {
  value = {
    # existing ...
    <name> = module.<name>.vm_id
  }
}
```

### Step 4 — Update `ansible/inventory/hosts.yaml`

Add under the `lxc` group:

```yaml
lxc-<name>:
  ansible_host: 192.168.8.<octet>
```

### Step 5 — Update `ansible/site.yaml`

The `Provision all LXC` play already applies base roles (`docker`, `node_exporter`, `cadvisor`) to every host. Add a separate play only for container-specific roles:

```yaml
- name: Deploy <Name>
  hosts: lxc-<name>
  roles:
    - <role1>
```

### Step 6 — Create `ansible/host_vars/lxc-<name>.yaml` (only if needed)

Only needed for host-specific variables (custom ports, `nas_puid`, `nas_pgid`):

```yaml
nas_puid: 3000
nas_pgid: 100
```

### Step 7 — Update `terraform/README.md`

Add a row to the **LXC containers** table:

```markdown
| lxc-<name> | <vm_id> | 192.168.8.<octet> | <purpose> |
```

## Removing an LXC Container

1. Delete `terraform/lxc-<name>.tf`
2. Remove `<name>` from all three maps in `variables.tf`
3. Remove `<name>` from both output blocks in `outputs.tf`
4. Remove the host from `ansible/inventory/hosts.yaml`
5. Remove the play from `ansible/site.yaml`
6. Delete `ansible/host_vars/lxc-<name>.yaml` if it exists
7. Remove the row from `terraform/README.md`

## Modifying an Existing Container

- Resource changes (CPU/memory/disk): edit the relevant `lxc-<name>.tf` and note in README if notable.
- Adding mounts: add to the `mounts` list in `lxc-<name>.tf`; add `nas_idmap` if NAS bind mounts need UID/GID mapping.
- Changing IPs: update `variables.tf` AND `ansible/inventory/hosts.yaml` together.

## Module Reference

The `modules/lxc` module creates an unprivileged Proxmox LXC with:

- Ubuntu 24.04 by default (`lxc_template`)
- Two network interfaces: `eth0` (vmbr0, primary LAN `192.168.8.x`) and `eth1` (vmbr1, secondary `192.168.50.x`)
- `nesting = true` enabled for Docker
- Mounts applied via `pct set` post-provisioning
