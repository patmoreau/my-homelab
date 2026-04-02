# Terraform Setup

## Homelab SSH key

```bash
ssh-keygen -t ed25519 -C "terraform-homelab" -f ~/.ssh/terraform_homelab -N ""
chmod 600 ~/.ssh/terraform_homelab
```

### Strict Permissions

```bash
chmod 600 ~/.ssh/terraform_homelab
```

### Set usage limits

`~/.ssh/config`

```text
Host proxmox
  HostName proxmox.homelab.lan
  User terraform-admin
  IdentityFile ~/.ssh/terraform_homelab
  IdentitiesOnly yes
```

### Allow sudo for terraform-admin

```bash
echo 'terraform-admin ALL=(ALL) NOPASSWD: /usr/sbin/pct, /usr/bin/tee' > /etc/sudoers.d/terraform-admin
```
