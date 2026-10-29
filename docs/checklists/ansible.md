# Ansible — Role and Playbook Checklist

Follow this checklist when creating, modifying, or removing an Ansible role or playbook.

## README & Lint Rules

> See the canonical [README Update Rule](../../AGENTS.md#readme-update-rule-always-apply)
> and [Ansible Linting rule](../../AGENTS.md#ansible-linting-always-apply) in `AGENTS.md`.
> For Ansible: update `ansible/README.md` when adding a role, host, or vault secret, and
> run `cd ansible && ansible-lint` (0 failures) before committing.

## Key Variables

| Variable                | Value              | Notes                                            |
| ----------------------- | ------------------ | ------------------------------------------------ |
| `docker_compose_dir`    | `/opt/docker`      | Base dir for per-service config and env files    |
| `ansible_user`          | `root`             | Ansible connects as root                         |
| `timezone`              | `America/Montreal` |                                                  |
| `nas_puid` / `nas_pgid` | `0` / `0`          | Group default; override per host in `host_vars/` |

## Creating a New Role

### Step 1 — Create the role directory

```
ansible/roles/<name>/
  tasks/
    main.yaml
  templates/            # only if role has config or env files
    <name>.container               # Quadlet unit — Renovate bumps Image= here
    <name>.env.j2                  # OPTIONAL — secrets/per-host values, rendered by Ansible
    <name>.container.j2            # OPTIONAL — only when the unit needs Jinja2
```

> **Important — Renovate compatibility:** the `Image=` line must be in a plain `.container`
> (or `.container.j2`) file under `ansible/roles/*/templates/`. `renovate.json` has a
> `customManager` that matches `Image=<name>:<tag>` there. Keep secrets out of the unit:
> put them in a `<name>.env.j2` rendered to `{{ docker_compose_dir }}/<name>/<name>.env`
> and reference it with `EnvironmentFile=`, so the unit can stay plain and mode `0644`.

### Step 2 — Write `tasks/main.yaml` and `tasks/podman.yaml`

`tasks/main.yaml` creates the directories and config files, then includes the Quadlet
tasks. Follow the pattern used by `homepage` and the other roles:

```yaml
- name: Create directory
  ansible.builtin.file:
    path: "{{ docker_compose_dir }}/<name>"
    state: directory
    mode: "0755"

# Add tasks for additional config files or directories here, before the include.

- name: Deploy via Podman Quadlet
  ansible.builtin.include_tasks: podman.yaml
```

`tasks/podman.yaml` renders the env file and the unit, then starts the service. It must
restart (not just start) when either changes:

```yaml
- name: Ensure Quadlet directory exists
  ansible.builtin.file:
    path: /etc/containers/systemd
    state: directory
    mode: "0755"

- name: Create <name> env file
  ansible.builtin.template:
    src: <name>.env.j2
    dest: "{{ docker_compose_dir }}/<name>/<name>.env"
    mode: "0600"
  register: <name>_env

- name: Deploy <name> Quadlet unit
  ansible.builtin.template:
    src: <name>.container
    dest: /etc/containers/systemd/<name>.container
    mode: "0644"
  register: <name>_quadlet

- name: Start <name>
  ansible.builtin.systemd:
    name: <name>.service
    state: "{{ 'restarted' if (<name>_quadlet.changed or <name>_env.changed) else 'started' }}"
    daemon_reload: true
```

Multi-container apps (a database plus an app, for example) follow the same shape with one
unit per container. Use `Requires=`/`After=` in the unit, and `Network=container:<owner>`
when a container shares another's netns. See `vaultwarden` and `immich`.

### Step 3 — Write `templates/<name>.container` (plain, Renovate-managed)

Keep it plain — **no Jinja2** — so Renovate can bump `Image=`. Secrets and per-host values
come from the `EnvironmentFile=`:

```ini
[Unit]
Description=<Name>

[Container]
ContainerName=<name>
Image=<image>:<tag>
Volume=/opt/docker/<name>/config:/config
EnvironmentFile=/opt/docker/<name>/<name>.env

[Service]
Restart=always

[Install]
WantedBy=default.target
```

**Only if a value genuinely needs Jinja2** (host lookups, per-host group IDs such as a
render GID), put it in `templates/<name>.container.j2`. Keep the `Image=` line there too so
Renovate still matches it. Quadlet on podman 4.9 has no `GroupAdd=`, so pass it through
`PodmanArgs=--group-add <gid>`. See `immich`.

Reference vault secrets in the `<name>.env.j2` template as `{{ vault_<name>_<field> }}`.

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

### Step 4b — Monitor the service

Follow the [Monitoring Rule](../../AGENTS.md#monitoring-rule-always-apply): add a blackbox
probe with a `service:` label to `roles/prometheus/templates/prometheus.yml.j2`. Pick the
module by what the endpoint returns:

| Endpoint | Module |
| -------- | ------ |
| Plain 2xx (the default) | job default, no label needed |
| Basic-auth UI answering 401 | `__param_module: 'http_2xx_or_401'` |
| Self-signed HTTPS appliance UI | `__param_module: 'http_2xx_insecure'` plus `cert_check: 'off'` |

The Grafana board and the homepage down-count need no edit; they list every probe.

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
