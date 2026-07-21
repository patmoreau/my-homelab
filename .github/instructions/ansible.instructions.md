---
description: "Use when creating a new Ansible role, adding a service to an existing LXC container, modifying playbooks or inventory, working with vault secrets, writing Docker Compose templates, or configuring host variables. Includes the full role creation checklist and README update requirement."
applyTo: "ansible/**"
---

# Ansible — Role and Playbook Instructions

## README Update Rule

> See the canonical [README Update Rule](../../AGENTS.md#readme-update-rule-always-apply).
> For Ansible: update `ansible/README.md` when adding a role, a host, or a vault secret.

## Linting (Always Apply)

> **Before committing any change under `ansible/`, run the linter and ensure it passes:**
>
> ```bash
> cd ansible && ansible-lint
> ```
>
> It must report **0 failures** (`Passed`). Fix the findings before committing. Rule
> configuration lives in `ansible/.ansible-lint` — only add a rule to its `skip_list` /
> `exclude_paths` for genuinely opinionated rules or non-Ansible files, not to silence a
> real issue. `ansible-lint` is installed locally (Red Hat Ansible VS Code extension / pip).

## Key Variables

| Variable                | Value              | Notes                                            |
| ----------------------- | ------------------ | ------------------------------------------------ |
| `docker_compose_dir`    | `/opt/docker`      | Base dir for all Docker Compose projects         |
| `ansible_user`          | `root`             | Ansible connects as root                         |
| `timezone`              | `America/Montreal` |                                                  |
| `nas_puid` / `nas_pgid` | `0` / `0`          | Group default; override per host in `host_vars/` |

## Creating a New Role

### Step 1 — Create the role directory

```
ansible/roles/<name>/
  tasks/
    main.yaml
  templates/            # only if role uses Docker Compose or config files
    docker-compose.yaml            # plain YAML (no .j2) — Renovate reads image tags here
    docker-compose.override.yaml.j2  # OPTIONAL — only when a value needs Jinja2
```

> **Important — Renovate compatibility:** the base compose file must be plain
> `docker-compose.yaml` (no `.j2` extension) and contain no Jinja2, so Renovate's
> docker-compose manager can find and bump the `image:` tags. Put any Jinja2-templated
> values (host lookups, per-host vars, `{{ ... }}`) in a separate
> `docker-compose.override.yaml.j2`, which Docker Compose auto-merges at `up` time.
> Prefer plain docker `${ENV}` interpolation (via a templated `.env`) over Jinja2 where
> possible — that keeps everything in the base file.

### Step 2 — Write `tasks/main.yaml`

Follow the standard Docker Compose pattern used by all existing roles:

```yaml
- name: Create directory
  ansible.builtin.file:
    path: "{{ docker_compose_dir }}/<name>"
    state: directory
    mode: "0755"

- name: Copy docker-compose.yaml
  ansible.builtin.template:
    src: docker-compose.yaml
    dest: "{{ docker_compose_dir }}/<name>/docker-compose.yaml"
    mode: "0644"

# OPTIONAL — only if the role needs a Jinja2 override (see Step 3)
- name: Copy docker-compose.override.yaml
  ansible.builtin.template:
    src: docker-compose.override.yaml.j2
    dest: "{{ docker_compose_dir }}/<name>/docker-compose.override.yaml"
    mode: "0644"

- name: Start
  community.docker.docker_compose_v2:
    project_src: "{{ docker_compose_dir }}/<name>"
    state: present
```

Add tasks for additional config files or directories **before** the `Start` task.

### Step 3 — Write `templates/docker-compose.yaml` (plain, Renovate-managed)

Keep it plain YAML — **no Jinja2** — so Renovate can bump the `image:` tags. Use docker
`${ENV}` interpolation (fed by a templated `.env`) for secrets/per-host values:

```yaml
services:
  <name>:
    image: <image>:<tag>
    container_name: <name>
    restart: unless-stopped
    environment:
      - PUID=${PUID}
      - PGID=${PGID}
      - TZ=${TZ}
    volumes:
      - /opt/docker/<name>/config:/config
    labels:
      - "traefik.enable=true"
      - "traefik.http.routers.<name>.rule=Host(`<name>.homelab.lan`)"
```

**Only if a value genuinely needs Jinja2** (host lookups like
`{{ hostvars[...] }}`, per-host group IDs, etc.), add
`templates/docker-compose.override.yaml.j2` containing *only* the templated keys, and wire
up the optional override task from Step 2. Keep every `image:` line in the plain base file
so Renovate still sees it. Compose auto-merges the override; because the base omits the
templated key entirely, the merge yields exactly the override's value. Example
(`immich` / `traefik` follow this pattern):

```yaml
services:
  <service>:
    group_add:
      - "{{ some_gid }}"
```

Reference vault secrets in the `.env` template as `${VAR}` fed from `{{ vault_<name> }}`.

### Step 4 — Add the role to `ansible/site.yaml`

Identify which host(s) should run this role:

- **All LXC hosts** → add to the `Provision all LXC` play
- **Specific host** → add to that host's existing play, or create a new play:

```yaml
- name: Deploy <Name>
  hosts: lxc-<hostname>
  roles:
    - <name>
```

### Step 5 — Add vault secrets (if applicable)

If the role needs secrets:

1. Add variable(s) to `ansible/group_vars/all/vault.yaml` (plaintext, gitignored)
2. Re-encrypt: `cd ansible && ./vault.sh encrypt`
3. Update `ansible/README.md` — add rows to the vault variables table:

```markdown
| `vault_<name>_<field>` | <role_name> | <description> |
```

### Step 6 — Update `ansible/README.md`

Document any new roles that introduce vault secrets or significant services.

## Modifying an Existing Role

- Edit `tasks/main.yaml` and/or files in `templates/`.
- If new vault variables are added, follow Step 5 above.
- If the role's host assignment changes, update `site.yaml`.
- Always update `ansible/README.md` when vault variables change.

## Removing a Role

1. Delete the `ansible/roles/<name>/` directory.
2. Remove the role from `ansible/site.yaml`.
3. Remove any vault variables it used from `vault.yaml` and re-encrypt.
4. Update `ansible/README.md` to remove entries from the vault table.

## Vault Workflow

```bash
cd ansible
./vault.sh edit      # decrypt, open editor, re-encrypt in one step
./vault.sh encrypt   # after manually editing vault.yaml
./vault.sh decrypt   # on a new machine, restore plaintext
```

Never commit `vault.yaml` (plaintext). Always commit `vault.yaml.vault` (encrypted).

## Host Variables

Create `ansible/host_vars/lxc-<name>.yaml` only when a host needs values that differ from group defaults:

```yaml
nas_puid: 3000
nas_pgid: 100
some_custom_var: value
```

## Inventory

All LXC hosts are defined in `ansible/inventory/hosts.yaml` under the `lxc` group. When a new LXC container is provisioned via Terraform, its entry must be added here before Ansible can connect.
