# Homelab Agent Instructions

Canonical guidance for all AI agents (Claude, Gemini, Copilot, …) working in this
repository. The tool-specific entry files and per-directory `AGENTS.md` files just point
here — **keep shared facts in this file only, so nothing drifts out of sync.**

## Project Overview

A Proxmox-based home server, managed as code in three lanes:

- **Terraform** (`terraform/`) — provisions unprivileged LXC containers on Proxmox via the
  `bpg/proxmox` provider.
- **Ansible** (`ansible/`) — configures services inside the LXCs (`site.yaml`) and the
  Proxmox host itself (`proxmox.yaml`). Services are Docker Compose stacks deployed by
  roles (Immich, Jellyfin, Vaultwarden, monitoring, …).
- **Tools** (`tools/`) — custom Node.js utilities (e.g. `service-watcher`).

Host-level how-tos (GPU passthrough, VLANs, NFS mapping, the Proxmox host setup) live in
`docs/`.

## General Conventions

- LXC containers are named `lxc-<name>` (e.g. `lxc-media`, `lxc-tools`).
- Networks: primary `192.168.8.x` (eth0/vmbr0); secondary `192.168.50.x` (eth1/vmbr1).
- Ansible connects to LXCs as `root` with `~/.ssh/terraform_homelab`. The **Proxmox host**
  (`pve-homelab`) is the exception — it connects as `terraform-admin` with `become`.
- Docker services live under `/opt/docker/<service>/` on each LXC, started with
  `community.docker.docker_compose_v2`.
- Secrets live in `ansible/group_vars/all/vault.yaml` (gitignored plaintext), committed
  only in encrypted form as `vault.yaml.vault`.

## README Update Rule (Always Apply)

> **When you change a component, update the relevant README in the same change.**

| Change                                | README to update                |
| ------------------------------------- | ------------------------------- |
| Add / remove an LXC container         | `terraform/README.md`           |
| Modify a Terraform variable or module | `terraform/README.md`           |
| Add / remove an Ansible role          | `ansible/README.md`             |
| Add a vault secret                    | `ansible/README.md` vault table |
| Add a host to inventory               | `ansible/README.md`             |

## Detailed Guides

Read the matching guide before working in that area — they hold the full step-by-step
checklists:

- **Terraform / LXC containers** → [`.github/instructions/terraform.instructions.md`](.github/instructions/terraform.instructions.md)
- **Ansible roles & playbooks** → [`.github/instructions/ansible.instructions.md`](.github/instructions/ansible.instructions.md)

## Instruction File Layout

This file is the single source of truth for shared context. The rest are thin pointers —
**do not copy content into them:**

| File                                       | Role                                                    |
| ------------------------------------------ | ------------------------------------------------------- |
| `AGENTS.md`                                | Canonical shared instructions (this file)               |
| `CLAUDE.md`                                | Claude entry — imports this file + the two guides       |
| `GEMINI.md`                                | Gemini entry — imports this file                        |
| `.github/copilot-instructions.md`          | Copilot entry — points here                             |
| `ansible/AGENTS.md`, `terraform/AGENTS.md` | Directory pointers to each detailed guide               |
| `.github/instructions/*.instructions.md`   | Detailed per-area checklists (Copilot auto-applies by path via `applyTo`) |
