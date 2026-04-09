# Homelab — GitHub Copilot Workspace Instructions

## Project Overview

Proxmox homelab managed with Terraform (LXC provisioning) and Ansible (service configuration).

- `terraform/` — provisions LXC containers via `bpg/proxmox` provider
- `ansible/` — configures Docker services inside each LXC
- LXC names follow the pattern `lxc-<name>`
- Primary network: `192.168.8.x` (eth0); secondary: `192.168.50.x` (eth1)
- Ansible connects as `root` with `~/.ssh/terraform_homelab`
- Docker services run under `/opt/docker/<service>/` using `community.docker.docker_compose_v2`

## README Update Rule — Always Apply

Whenever you create or modify a component, also update the corresponding README:

| Change                                  | README to update                |
| --------------------------------------- | ------------------------------- |
| Adding / removing an LXC container      | `terraform/README.md`           |
| Modifying Terraform variables or module | `terraform/README.md`           |
| Adding / removing an Ansible role       | `ansible/README.md`             |
| Adding secrets to vault.yaml            | `ansible/README.md` vault table |
| Adding a new host to inventory          | `ansible/README.md`             |

## Context-Specific Instructions

Detailed checklists are in dedicated instruction files loaded automatically by file pattern:

- **Terraform** (`terraform/**`) → `.github/instructions/terraform.instructions.md`
- **Ansible** (`ansible/**`) → `.github/instructions/ansible.instructions.md`
