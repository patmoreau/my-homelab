# my-homelab — Agent Instructions

Canonical instructions for any coding agent working in this repository. Everything shared
lives here (always loaded); the detailed per-lane checklists live in `docs/checklists/` —
see **Checklists** below.

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
- Secrets live in alphabetical order in `ansible/group_vars/all/vault.yaml` (gitignored plaintext), committed
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

## Ansible Linting (Always Apply)

> Before committing any change under `ansible/`, run `cd ansible && ansible-lint` and
> ensure it reports **0 failures**. Fix findings first. Rule config is in
> `ansible/.ansible-lint` — only skip/exclude genuinely opinionated rules or non-Ansible
> files, never to silence a real issue.

## Working Agreements

- **Trunk-based:** commit directly to `main`. Do not create a feature branch unless the user
  explicitly asks for one.
- **Detection is not remediation:** a check for a known, mechanical fault must also repair
  it, with a two-strike guard so transients are never acted on. Keep alert-only for faults
  that need human judgement. When reporting a fix, say whether the fault was only detected
  or also remediated.

## Checklists

The full step-by-step checklists are on-demand. Read and follow the matching one before
working in that lane:

- **`docs/checklists/terraform.md`** — create / modify / remove an LXC container (Terraform).
- **`docs/checklists/ansible.md`** — create / modify / remove an Ansible role, plus vault,
  inventory, and host variables.

## Repository Instruction Layout

- `AGENTS.md` (this file) — canonical, always-loaded instructions for all agents.
- `CLAUDE.md` — one-line import of `AGENTS.md` so Claude Code loads the same file.
- `docs/checklists/{terraform,ansible}.md` — the detailed on-demand checklists.
- `docs/` — host-level how-to references.
