# Ansible

## What was set up

| File                                | Purpose                                     | Git        |
| ----------------------------------- | ------------------------------------------- | ---------- |
| ansible/group_vars/vault.yaml       | Plaintext secrets — Ansible reads this      | Gitignored |
| ansible/group_vars/vault.yaml.vault | Encrypted copy                              | Committed  |
| ansible/.vault_pass                 | Vault password file                         | Gitignored |
| ansible.cfg                         | Points Ansible at .vault_pass automatically | Committed  |
| vault.sh                            | Helper script                               | Committed  |

## Daily workflow

```bash
./vault.sh edit      # decrypt + open editor + re-encrypt in one step
./vault.sh encrypt   # after manually editing vault.yaml, save encrypted copy
./vault.sh decrypt   # on a new machine, restore plaintext from vault.yaml.vault
```

## Deploy playbook

### Ping lcx

```bash
ansible all -i inventory/hosts.yaml -m ping
```

### Deploy all

```bash
cd ~/homelab/ansible
ansible-playbook -i inventory/hosts.yaml site.yaml
```

### Deploy single

```bash
cd ~/homelab/ansible
ansible-playbook -i inventory/hosts.yaml site.yaml --limit lxc-traefik
```
