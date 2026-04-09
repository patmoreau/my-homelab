# Homelab Agent Instructions

General guidelines for all AI agents working in this homelab repository.

## Project Overview

This homelab repository manages infrastructure for a Proxmox-based home server with:

- **Terraform** (`terraform/`) — provisions LXC containers on Proxmox via the `bpg/proxmox` provider
- **Ansible** (`ansible/`) — configures services inside the LXC containers
- **Immich / Nextcloud** — standalone Docker Compose stacks
- **Tools** (`tools/`) — custom Node.js utilities (e.g. `service-watcher`)

## General Conventions

- LXC containers are named `lxc-<name>` (e.g. `lxc-media`, `lxc-tools`)
- Primary network: `192.168.8.x` (eth0, vmbr0); secondary: `192.168.50.x` (eth1, vmbr1)
- Ansible connects as `root` using `~/.ssh/terraform_homelab`
- Docker services live under `/opt/docker/<service>/` on each LXC
- Secrets are stored in `ansible/group_vars/all/vault.yaml` (gitignored) and encrypted in `vault.yaml.vault`

## README Update Rule (Always Apply)

> **When you modify any component, always update the relevant README to reflect the change.**

| Context changed                         | README to update                |
| --------------------------------------- | ------------------------------- |
| Adding / removing an LXC container      | `terraform/README.md`           |
| Modifying Terraform variables or module | `terraform/README.md`           |
| Adding / removing an Ansible role       | `ansible/README.md`             |
| Adding secrets to vault.yaml            | `ansible/README.md` vault table |
| Adding a new host to inventory          | `ansible/README.md`             |

## Context-Specific Instructions

- **Terraform / LXC containers** → `.github/instructions/terraform.instructions.md`
- **Ansible roles and playbooks** → `.github/instructions/ansible.instructions.md`
